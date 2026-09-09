from platform_runbooks.registry_schema import verify_scope_documents


def _scope(scope_id: str, group: str) -> dict[str, object]:
    return {
        "_id": scope_id,
        "group_mappings": [group],
        "ui_permissions": {
            "register_service": ["all"],
            "modify_service": ["all"],
            "delete_service": ["all"],
        },
    }


def test_schema_check_accepts_required_admin_scopes() -> None:
    result = verify_scope_documents(
        [_scope("mcp-registry-admin", "mcp-registry-admin"), _scope("registry-admins", "registry-admins")]
    )
    assert result["valid"] is True
    assert result["errors"] == []


def test_schema_check_reports_missing_scope_without_exposing_document_data() -> None:
    result = verify_scope_documents([_scope("mcp-registry-admin", "mcp-registry-admin")])
    assert result["valid"] is False
    assert result["errors"] == [{"scope": "registry-admins", "reason": "required scope document is missing"}]


def test_schema_check_rejects_wrong_permission_shape() -> None:
    document = _scope("mcp-registry-admin", "mcp-registry-admin")
    document["ui_permissions"] = {"register_service": "all"}
    result = verify_scope_documents([document, _scope("registry-admins", "registry-admins")])
    assert result["valid"] is False
    assert result["errors"][0]["scope"] == "mcp-registry-admin"


def test_live_schema_check_projects_only_schema_fields(monkeypatch) -> None:
    from platform_runbooks import registry_schema

    class Cursor:
        def __iter__(self):
            return iter([_scope("mcp-registry-admin", "mcp-registry-admin"), _scope("registry-admins", "registry-admins")])

    class Collection:
        def find(self, query, projection):
            assert query == {}
            assert projection == {"_id": 1, "group_mappings": 1, "ui_permissions": 1}
            return Cursor()

    class Client:
        def __getitem__(self, name):
            assert name == "mcp_registry"
            return {"mcp_scopes_default": Collection()}

        def close(self):
            pass

    monkeypatch.setattr(registry_schema, "MongoClient", lambda *args, **kwargs: Client())
    result = registry_schema.verify_scope_collection("mongodb+srv://redacted", "mcp_registry", "default")
    assert result["valid"] is True
    assert result["collection"] == "mcp_scopes_default"