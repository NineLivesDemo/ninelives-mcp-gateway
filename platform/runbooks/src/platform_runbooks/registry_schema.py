"""Fail-closed schema checks for Registry authorization scope documents."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from pymongo import MongoClient
from pymongo.errors import PyMongoError

_REQUIRED_SCOPES = frozenset({"mcp-registry-admin", "registry-admins"})
_REQUIRED_PERMISSION_KEYS = frozenset({"register_service", "modify_service", "delete_service"})


def _invalid(scope_id: str, reason: str) -> dict[str, object]:
    return {"scope": scope_id, "reason": reason}


def _validate_scope(document: object) -> dict[str, object] | None:
    if not isinstance(document, Mapping):
        return _invalid("<unknown>", "scope document must be an object")
    scope_id = document.get("_id")
    if not isinstance(scope_id, str) or not scope_id:
        return _invalid("<unknown>", "_id must be a non-empty string")
    groups = document.get("group_mappings")
    if not isinstance(groups, list) or not all(isinstance(group, str) and group for group in groups):
        return _invalid(scope_id, "group_mappings must be a list of non-empty strings")
    permissions = document.get("ui_permissions")
    if not isinstance(permissions, Mapping):
        return _invalid(scope_id, "ui_permissions must be an object")
    for action, resources in permissions.items():
        if not isinstance(action, str) or not isinstance(resources, list):
            return _invalid(scope_id, "ui_permissions values must be lists keyed by strings")
        if not all(isinstance(resource, str) and resource for resource in resources):
            return _invalid(scope_id, "ui_permissions resource grants must be non-empty strings")
    if scope_id in _REQUIRED_SCOPES and scope_id not in groups:
        return _invalid(scope_id, "required administrator scope is missing its matching group mapping")
    if scope_id == "mcp-registry-admin" and not _REQUIRED_PERMISSION_KEYS.issubset(permissions):
        return _invalid(scope_id, "required administrator permissions are missing")
    return None


def verify_scope_collection(
    connection_string: str,
    database_name: str = "mcp_registry",
    namespace: str = "default",
) -> dict[str, Any]:
    """Read and validate the live Registry scope collection."""
    if not connection_string.strip():
        raise ValueError("MongoDB connection string must be non-empty")
    collection_name = f"mcp_scopes_{namespace}"
    client = MongoClient(connection_string, serverSelectionTimeoutMS=10000)
    try:
        documents = list(
            client[database_name][collection_name].find(
                {}, {"_id": 1, "group_mappings": 1, "ui_permissions": 1}
            )
        )
    except PyMongoError as error:
        raise RuntimeError(f"MongoDB scope schema check failed for {collection_name}") from error
    finally:
        client.close()
    result = verify_scope_documents(documents)
    result["collection"] = collection_name
    return result


def verify_scope_documents(documents: object) -> dict[str, Any]:
    """Validate required Registry scope documents without writing to MongoDB."""
    if not isinstance(documents, Sequence) or isinstance(documents, (str, bytes)):
        return {"valid": False, "errors": [_invalid("<collection>", "must be a JSON array")]}
    errors = [error for document in documents if (error := _validate_scope(document))]
    by_id = {
        document.get("_id")
        for document in documents
        if isinstance(document, Mapping) and isinstance(document.get("_id"), str)
    }
    missing = sorted(_REQUIRED_SCOPES - by_id)
    errors.extend(_invalid(scope_id, "required scope document is missing") for scope_id in missing)
    return {
        "valid": not errors,
        "scope_count": len(documents),
        "required_scopes": sorted(_REQUIRED_SCOPES),
        "errors": errors,
    }
