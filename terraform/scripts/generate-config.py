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


def generate_helm_values(config, env):
    """Generate Helm umbrella chart values override from config."""
    spec = config.get("spec", {})
    components = spec.get("components", {})
    security = spec.get("security", {})
    observability = spec.get("observability", {})
    storage = spec.get("storage", {})
    inference = spec.get("inference", {})
    kubernetes = spec.get("kubernetes", {})

    # Map components → Helm chart toggles + values
    helm_values = {
        "global": {
            "clusterName": f"ai-platform-{env}",
            "environment": env,
            "region": spec.get("providers", {}).get("aws", {}).get("region", "us-west-2"),
        },
    }

    # Networking
    networking = components.get("networking", {})
    helm_values["cilium"] = {
        "enabled": networking.get("cni") == "cilium",
        "hubble": {"enabled": True, "relay": {"enabled": True}, "ui": {"enabled": True}},
        "encryption": {"enabled": True, "type": "wireguard"},
        "gatewayAPI": {"enabled": True},
    }

    cert = networking.get("certManager", {})
    helm_values["cert-manager"] = {
        "enabled": cert.get("enabled", False),
        "installCRDs": True,
    }

    helm_values["gateway-api"] = {
        "enabled": True,
        "experimentalChannel": True,
    }

    # GitOps
    gitops = components.get("gitops", {})
    helm_values["argo-cd"] = {
        "enabled": gitops.get("type") == "argocd",
        "configs": {
            "params": {"server.insecure": True},
            "cm": {"timeout.reconciliation": "60s"},
        },
    }

    # Security
    policy = components.get("security", {}).get("policy", {})
    helm_values["kyverno"] = {
        "enabled": policy.get("engine") == "kyverno",
        "mode": policy.get("mode", "audit"),
    }

    secrets_engine = components.get("security", {}).get("secrets", {})
    helm_values["external-secrets"] = {
        "enabled": secrets_engine.get("engine") == "external-secrets",
        "installCRDs": True,
    }

    vault = components.get("security", {}).get("vault", {})
    helm_values["vault"] = {
        "enabled": vault.get("enabled", False),
        "ha": {"enabled": True, "replicas": 3, "raft": {"enabled": True}},
    }

    helm_values["opa-gatekeeper"] = {"enabled": False}

    # Observability
    obs = observability
    helm_values["kube-prometheus-stack"] = {
        "enabled": obs.get("metrics", {}).get("stack") == "kube-prometheus-stack",
        "prometheus": {
            "retention": obs.get("metrics", {}).get("retention", "7d"),
            "storageSize": obs.get("metrics", {}).get("storageSize", "20Gi"),
        },
    }

    helm_values["grafana"] = {
        "enabled": obs.get("dashboards", {}).get("enabled", False),
        "adminUser": obs.get("dashboards", {}).get("grafana", {}).get("adminUser", "admin"),
        "adminPassword": obs.get("dashboards", {}).get("grafana", {}).get("adminPassword", "${GRAFANA_PASSWORD}"),
    }

    helm_values["loki"] = {
        "enabled": obs.get("logging", {}).get("backend") == "loki",
        "retention": obs.get("logging", {}).get("retention", "3d"),
        "storageSize": obs.get("logging", {}).get("storageSize", "20Gi"),
    }

    helm_values["tempo"] = {
        "enabled": obs.get("tracing", {}).get("backend") == "tempo",
        "retention": obs.get("tracing", {}).get("retention", "3d"),
        "sampling": obs.get("tracing", {}).get("sampling", 0.1),
    }

    helm_values["opentelemetry-operator"] = {
        "enabled": obs.get("tracing", {}).get("backend") is not None,
        "autoInstrumentation": {"enabled": True, "python": True, "nodejs": True},
    }

    # Storage
    storage_config = components.get("storage", {})
    helm_values["cnpg"] = {
        "enabled": storage_config.get("postgres", {}).get("enabled", False),
    }
    helm_values["dragonfly"] = {
        "enabled": storage_config.get("redis", {}).get("enabled", False),
        "replicas": 3,
        "persistence": {"size": "20Gi"},
    }
    helm_values["velero"] = {
        "enabled": storage_config.get("backup", {}).get("enabled", False),
        "schedule": storage_config.get("backup", {}).get("schedule", "0 2 * * *"),
        "retention": storage_config.get("backup", {}).get("retention", "7d"),
    }

    # Cost
    helm_values["opencost"] = {
        "enabled": components.get("cost", {}).get("enabled", False),
    }

    # AI Infrastructure
    ai = components.get("ai", {})
    helm_values["gpu-operator"] = {
        "enabled": ai.get("gpuOperator", True),
        "timeSlicing": {"enabled": True, "count": 4, "resources": ["nvidia.com/gpu"]},
    }

    helm_values["kserve"] = {
        "enabled": ai.get("kserve", True),
        "controller": {"imageTag": f"v{ai.get('kserveVersion', '0.14.0')}"},
        "vllm": {"enabled": True, "runtime": "vllm"},
    }

    helm_values["keda"] = {
        "enabled": ai.get("keda", True),
        "prometheus": {"enabled": True},
    }

    helm_values["kueue"] = {
        "enabled": ai.get("kueue", True),
        "resources": ["cpu", "memory", "nvidia.com/gpu"],
    }

    # AI serving
    model = inference.get("model", {})
    serving = inference.get("serving", {})
    autoscaling = inference.get("autoscaling", {})

    helm_values["llm-d"] = {
        "enabled": ai.get("llm-d", False),
        "backend": serving.get("engine", "vllm"),
        "model": {
            "name": model.get("name", "google/gemma-2-2b-it").split("/")[-1],
            "tensorParallelism": serving.get("tensorParallelSize", 1),
            "pipelineParallelism": serving.get("pipelineParallelSize", 1),
        },
    }

    helm_values["ai-gateway"] = {
        "enabled": True,
        "model": model.get("name", "google/gemma-2-2b-it"),
        "pool": {
            "minReplicas": autoscaling.get("minReplicas", 1),
            "maxReplicas": autoscaling.get("maxReplicas", 3),
        },
    }

    return helm_values


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

    # Generate Helm values
    helm_values = generate_helm_values(config, env)
    helm_values_path = project_root / "charts" / "ai-platform" / "values-generated.yaml"
    with open(helm_values_path, "w") as f:
        yaml.dump(helm_values, f, default_flow_style=False, sort_keys=False)
    print(f"  Generated: {helm_values_path}")

    # Generate K8s manifests
    generate_k8s_manifests(config, env, str(project_root))

    print("\n✓ Configuration generation complete")
    print(f"  Terraform in: {env_dir}")
    print(f"  Helm values:  {helm_values_path}")


if __name__ == "__main__":
    main()
