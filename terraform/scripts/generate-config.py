#!/usr/bin/env python3
"""
Generate Terraform variables and platform manifests from the YAML config.
Usage: python3 generate-config.py config/demo.yaml --env dev
"""
import sys
import yaml
import json
import os
from pathlib import Path


def load_config(config_path):
    """Load and parse platform config YAML."""
    with open(config_path) as f:
        return yaml.safe_load(f)


def resolve_secrets(config):
    """Resolve ${VAR} references from environment variables."""
    import re

    def replace_secret(match):
        var_name = match.group(1)
        if var_name.startswith("VAULT:"):
            # Vault path:key format
            return os.environ.get(var_name, f"${{{var_name}}}")
        return os.environ.get(var_name, f"${{{var_name}}}")

    def walk(obj):
        if isinstance(obj, str):
            return re.sub(r'\$\{([^}]+)\}', replace_secret, obj)
        elif isinstance(obj, dict):
            return {k: walk(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [walk(v) for v in obj]
        return obj

    return walk(config)


def generate_tfvars(config, env):
    """Generate Terraform variable file from config."""
    spec = config.get("spec", {})
    providers = spec.get("providers", {})
    aws = providers.get("aws", {})
    kubernetes = spec.get("kubernetes", {})
    inference = spec.get("inference", {})
    components = spec.get("components", {})
    security = spec.get("security", {})

    # Map node groups from config
    gpu_groups = {}
    for name, ng in kubernetes.get("nodeGroups", {}).items():
        if ng.get("gpu"):
            gpu_groups[name] = {
                "instance_types": [ng["instanceType"]],
                "disk_size": ng.get("disk", 100),
                "min_size": ng["min"],
                "max_size": ng["max"],
                "spot": ng.get("spot", False),
                "accelerator": ng.get("gpu", {}).get("type", "nvidia-tesla-t4"),
                "labels": ng.get("labels", {}),
            }

    # Map IRSA roles
    irsa_roles = {
        "kube-system:cluster-autoscaler": {
            "policy_arns": [
                "arn:aws:iam::aws:policy/service-role/AmazonEKSClusterAutoscalerRole"
            ]
        },
        "kserve:kserve-controller": {
            "policy": json.dumps({
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:ListBucket",
                        "ecr:GetAuthorizationToken",
                        "ecr:BatchCheckLayerAvailability",
                        "ecr:GetDownloadUrlForLayer",
                        "ecr:BatchGetImage",
                    ],
                    "Resource": ["*"]
                }]
            })
        },
    }

    tfvars = {
        "name_prefix": "ai-platform",
        "environment": env,
        "region": aws.get("region", "us-west-2"),
        "account_role": aws.get("accounts", [{}])[0].get("role", "all-in-one"),
        "vpc_cidr": "10.0.0.0/16",
        "cluster_version": kubernetes.get("version", "1.31"),
        "karpenter_enabled": kubernetes.get("karpenter", {}).get("enabled", False),
        "system_instance_types": [
            kubernetes.get("nodeGroups", {}).get("system", {}).get("instanceType", "t3.medium")
        ],
        "system_min_size": kubernetes.get("nodeGroups", {}).get("system", {}).get("min", 1),
        "system_max_size": kubernetes.get("nodeGroups", {}).get("system", {}).get("max", 3),
        "gpu_node_groups": gpu_groups,
        "irsa_roles": irsa_roles,
        "gcp_enabled": providers.get("multi-cloud", {}).get("enabled", False),
        "enable_nat_gateway": True,
        "single_nat_gateway": False,
        "enable_transit_gateway": spec.get("networking", {}).get("cross_account", {}).get("enabled", False),
        "endpoint_private_access": True,
        "endpoint_public_access": not security.get("networkPolicies", {}).get("default_deny", True),
        "tags": {
            "Environment": env,
            "ManagedBy": "terraform",
            "Project": "ai-platform",
        },
    }

    return tfvars


def generate_k8s_manifests(config, env, output_dir):
    """Generate Kubernetes manifests for model serving."""
    spec = config.get("spec", {})
    inference = spec.get("inference", {})
    model = inference.get("model", {})
    serving = inference.get("serving", {})
    autoscaling = inference.get("autoscaling", {})

    model_name = model.get("name", "google/gemma-2-2b-it")
    model_short = model_name.split("/")[-1]
    hf_token_var = model.get("hf_token", "${HF_TOKEN}")
    tensor_parallel = serving.get("tensorParallelSize", 1)
    max_len = serving.get("maxModelLen", 8192)
    dtype = serving.get("dtype", "bfloat16")
    gpu_mem = serving.get("gpuMemoryUtilization", 0.90)
    min_replicas = autoscaling.get("minReplicas", 1)
    max_replicas = autoscaling.get("maxReplicas", 3)
    prefix_cache = serving.get("enablePrefixCaching", True)

    # AI directory
    ai_dir = Path(output_dir) / "ai" / "kserve"
    ai_dir.mkdir(parents=True, exist_ok=True)

    # LLMInferenceService
    llmisvc = {
        "apiVersion": "serving.kserve.io/v1alpha1",
        "kind": "LLMInferenceService",
        "metadata": {
            "name": model_short,
            "namespace": "ai-inference",
        },
        "spec": {
            "model": {
                "uri": f"hf://{model_name}",
                "name": model_name,
            },
            "replicas": min_replicas,
            "template": {
                "containers": [{
                    "name": "main",
                    "image": "vllm/vllm-openai:latest",
                    "args": [
                        "--model", "/mnt/models",
                        "--tensor-parallel-size", str(tensor_parallel),
                        "--max-model-len", str(max_len),
                        "--dtype", dtype,
                        "--gpu-memory-utilization", str(gpu_mem),
                    ],
                    "resources": {
                        "limits": {
                            "nvidia.com/gpu": str(tensor_parallel),
                            "cpu": "8",
                            "memory": "32Gi",
                        }
                    },
                    "readinessProbe": {
                        "httpGet": {"path": "/health", "port": 8080},
                        "initialDelaySeconds": 60,
                        "periodSeconds": 10,
                    },
                    "livenessProbe": {
                        "httpGet": {"path": "/health", "port": 8080},
                        "initialDelaySeconds": 120,
                        "periodSeconds": 30,
                    },
                    "lifecycle": {
                        "preStop": {
                            "exec": {"command": ["/bin/sh", "-c", "sleep 30"]}
                        }
                    },
                }],
            },
            "router": {
                "gateway": {},
                "route": {},
                "scheduler": {},
            },
        },
    }

    if prefix_cache:
        llmisvc["spec"]["template"]["containers"][0]["args"].append("--enable-prefix-caching")

    llmisvc_path = ai_dir / f"llminferenceservice-{model_short}.yaml"
    with open(llmisvc_path, "w") as f:
        yaml.dump(llmisvc, f, default_flow_style=False)
    print(f"  Generated: {llmisvc_path}")

    # KEDA ScaledObject
    if autoscaling.get("enabled", False):
        scaled_object = {
            "apiVersion": "keda.sh/v1alpha1",
            "kind": "ScaledObject",
            "metadata": {
                "name": f"{model_short}-scaler",
                "namespace": "ai-inference",
            },
            "spec": {
                "scaleTargetRef": {
                    "apiVersion": "serving.kserve.io/v1alpha1",
                    "kind": "LLMInferenceService",
                    "name": model_short,
                },
                "pollingInterval": 15,
                "cooldownPeriod": autoscaling.get("cooldownPeriod", 300),
                "minReplicaCount": min_replicas,
                "maxReplicaCount": max_replicas,
                "triggers": [],
            },
        }

        for metric in autoscaling.get("metrics", []):
            if metric["type"] == "queue_depth":
                scaled_object["spec"]["triggers"].append({
                    "type": "prometheus",
                    "metricType": "AverageValue",
                    "metadata": {
                        "serverAddress": "http://prometheus.monitoring.svc.cluster.local:9090",
                        "metricName": "vllm_queue_depth",
                        "query": f'avg(vllm:num_requests_waiting{{namespace="ai-inference"}})',
                        "threshold": str(metric["threshold"]),
                    },
                })
            elif metric["type"] == "kv_cache":
                scaled_object["spec"]["triggers"].append({
                    "type": "prometheus",
                    "metricType": "AverageValue",
                    "metadata": {
                        "serverAddress": "http://prometheus.monitoring.svc.cluster.local:9090",
                        "metricName": "vllm_kv_cache_usage",
                        "query": f'avg(vllm:gpu_cache_usage_perc{{namespace="ai-inference"}})',
                        "threshold": str(metric["threshold"]),
                    },
                })

        so_path = Path(output_dir) / "ai" / "keda" / "scaled-object.yaml"
        so_path.parent.mkdir(parents=True, exist_ok=True)
        with open(so_path, "w") as f:
            yaml.dump(scaled_object, f, default_flow_style=False)
        print(f"  Generated: {so_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: generate-config.py <config.yaml> [--env ENV]")
        sys.exit(1)

    config_path = sys.argv[1]
    env = "dev"
    if "--env" in sys.argv:
        idx = sys.argv.index("--env")
        env = sys.argv[idx + 1]

    project_root = Path(__file__).parent.parent.parent

    print(f"Generating configuration from: {config_path}")
    print(f"Environment: {env}")

    # Load config
    config = load_config(config_path)
    config = resolve_secrets(config)

    # Generate Terraform variables
    tfvars = generate_tfvars(config, env)

    # Write terraform.tfvars
    env_dir = project_root / "terraform" / "envs" / env
    env_dir.mkdir(parents=True, exist_ok=True)

    tfvars_path = env_dir / "terraform.tfvars.json"
    with open(tfvars_path, "w") as f:
        json.dump(tfvars, f, indent=2)
    print(f"  Generated: {tfvars_path}")

    # Generate K8s manifests
    generate_k8s_manifests(config, env, str(project_root))

    print("\n✓ Configuration generation complete")
    print(f"  Templates in: {env_dir}")


if __name__ == "__main__":
    main()
