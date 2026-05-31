#!/usr/bin/env python3
"""
Validate platform configuration YAML against schema.
Usage: python3 validate-config.py config/demo.yaml
"""
import sys
import yaml
import json
from pathlib import Path

REQUIRED_FIELDS = [
    ("apiVersion", str),
    ("kind", str),
    ("metadata", dict),
    ("metadata.name", str),
    ("metadata.environment", str),
    ("spec", dict),
    ("spec.providers", dict),
    ("spec.providers.primary", str),
    ("spec.kubernetes", dict),
    ("spec.kubernetes.kind", str),
    ("spec.inference", dict),
    ("spec.inference.model", dict),
    ("spec.inference.model.name", str),
    ("spec.components", dict),
]

ENUM_FIELDS = {
    "spec.providers.primary": ["aws", "gcp", "azure"],
    "spec.kubernetes.kind": ["eks", "gke", "aks"],
    "spec.components.gitops.type": ["argocd", "flux"],
    "spec.components.networking.cni": ["cilium", "calico", "flannel"],
    "spec.components.networking.ingress.type": ["gateway-api", "ingress-nginx"],
    "spec.components.security.policy.engine": ["kyverno", "opa-gatekeeper"],
}

CONDITIONAL_REQUIRED = {
    "spec.gcp.enabled": [
        ("spec.gcp.project", "gcp.project required when gcp is enabled"),
    ],
    "spec.networking.cross_cloud.enabled": [
        ("spec.networking.cross_account.enabled", "cross_cloud requires cross_account"),
    ],
}


def get_nested(d, path):
    """Get nested dict value by dot path."""
    for key in path.split("."):
        if isinstance(d, dict):
            d = d.get(key)
        else:
            return None
    return d


def validate_config(config_path):
    """Validate a config file against the schema."""
    errors = []
    warnings = []

    try:
        with open(config_path) as f:
            config = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"ERROR: Invalid YAML: {e}")
        return False
    except FileNotFoundError:
        print(f"ERROR: File not found: {config_path}")
        return False

    if config is None:
        print("ERROR: Empty config file")
        return False

    # Check required fields
    for field, field_type in REQUIRED_FIELDS:
        value = get_nested(config, field)
        if value is None:
            errors.append(f"Missing required field: {field}")
        elif field_type == str and not isinstance(value, str):
            errors.append(f"Field {field} must be a string, got {type(value).__name__}")
        elif field_type == dict and not isinstance(value, dict):
            errors.append(f"Field {field} must be a dict, got {type(value).__name__}")

    # Check enum fields
    for field, allowed in ENUM_FIELDS.items():
        value = get_nested(config, field)
        if value is not None and value not in allowed:
            errors.append(f"Field {field} must be one of {allowed}, got '{value}'")

    # Check conditional required
    for condition, requirements in CONDITIONAL_REQUIRED.items():
        cond_value = get_nested(config, condition)
        if cond_value is True:
            for req_field, msg in requirements:
                req_value = get_nested(config, req_field)
                if req_value is None or req_value is False:
                    errors.append(msg)

    # Security recommendations
    sec = get_nested(config, "spec.security.networkPolicies.default_deny")
    if sec is False:
        warnings.append("WARNING: Network policy default-deny is disabled (recommended for production)")

    # Output results
    env = get_nested(config, "spec.environment") or "unknown"
    print(f"\nConfig: {config_path}")
    print(f"Environment: {env}")
    print(f"Provider: {get_nested(config, 'spec.providers.primary')}")
    print(f"Model: {get_nested(config, 'spec.inference.model.name')}")
    print(f"K8s: {get_nested(config, 'spec.kubernetes.kind')} v{get_nested(config, 'spec.kubernetes.version')}")
    print(f"Components: {list(get_nested(config, 'spec.components.ai').keys()) if get_nested(config, 'spec.components.ai') else 'N/A'}")
    print()

    if errors:
        print("ERRORS:")
        for e in errors:
            print(f"  - {e}")
    else:
        print("✓ All required fields present")

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  - {w}")

    if errors:
        return False

    print("\n✓ Config is valid")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: validate-config.py <config.yaml>")
        sys.exit(1)

    success = validate_config(sys.argv[1])
    sys.exit(0 if success else 1)
