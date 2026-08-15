"""Unit tests for the raw_array response adapter in LiteLLMClient.

Covers the EMBEDDINGS_RESPONSE_FORMAT=raw_array path, where the endpoint returns a
bare array of vectors instead of the OpenAI envelope, so the registry calls the
endpoint directly (bypassing litellm) and extracts the vectors itself.
"""

from unittest.mock import MagicMock, patch

import httpx
import numpy as np
import pytest

from registry.embeddings.client import (
    LiteLLMClient,
    _extract_openai_embeddings,
    _extract_raw_array,
    create_embeddings_client,
)


class TestExtractRawArray:
    """Tests for the _extract_raw_array parsing helper."""

    def test_bare_list_of_vectors(self):
        payload = [[0.1, 0.2], [0.3, 0.4]]
        assert _extract_raw_array(payload) == [[0.1, 0.2], [0.3, 0.4]]

    def test_dict_under_embeddings_key(self):
        payload = {"embeddings": [[0.1, 0.2]]}
        assert _extract_raw_array(payload) == [[0.1, 0.2]]

    def test_dict_under_data_key(self):
        payload = {"data": [[0.5, 0.6]]}
        assert _extract_raw_array(payload) == [[0.5, 0.6]]

    def test_dict_under_vectors_key(self):
        payload = {"vectors": [[0.7]]}
        assert _extract_raw_array(payload) == [[0.7]]

    def test_dict_without_known_key_raises(self):
        with pytest.raises(ValueError, match="without an"):
            _extract_raw_array({"result": "nope"})

    def test_empty_list_raises(self):
        with pytest.raises(ValueError, match="non-empty list"):
            _extract_raw_array([])

    def test_openai_envelope_list_of_dicts_raises(self):
        # A list of dicts (the OpenAI envelope's data) is not a raw array.
        with pytest.raises(ValueError, match="list of vectors"):
            _extract_raw_array([{"embedding": [0.1, 0.2]}])


class TestExtractOpenAIEmbeddings:
    """Tests for standard OpenAI-compatible embedding responses."""

    def test_extracts_embedding_vectors(self):
        payload = {"data": [{"embedding": [0.1, 0.2]}, {"embedding": [0.3, 0.4]}]}
        assert _extract_openai_embeddings(payload) == [[0.1, 0.2], [0.3, 0.4]]

    def test_rejects_missing_data(self):
        with pytest.raises(ValueError, match="'data' list"):
            _extract_openai_embeddings({"embeddings": [[0.1, 0.2]]})


class TestRawArrayEncode:
    """Tests for LiteLLMClient.encode() when response_format='raw_array'."""

    def _mock_response(self, json_body):
        response = MagicMock()
        response.json.return_value = json_body
        response.raise_for_status.return_value = None
        return response

    @patch("httpx.post")
    def test_encode_reads_bare_array(self, mock_post):
        mock_post.return_value = self._mock_response([[0.1] * 384, [0.2] * 384])

        client = LiteLLMClient(
            model_name="openai/mock-model",
            api_base="https://embeddings.example.com/v1",
            embedding_dimension=384,
            response_format="raw_array",
        )
        result = client.encode(["hello", "world"])

        assert isinstance(result, np.ndarray)
        assert result.shape == (2, 384)

    @patch("httpx.post")
    def test_encode_injects_bearer_and_strips_prefix(self, mock_post):
        mock_post.return_value = self._mock_response([[0.1, 0.2]])
        provider_fn = MagicMock(return_value="dynamic-token")

        client = LiteLLMClient(
            model_name="openai/mock-model",
            api_base="https://embeddings.example.com/v1/",
            embedding_dimension=2,
            token_provider=provider_fn,
            response_format="raw_array",
        )
        client.encode(["hi"])

        called_url = mock_post.call_args[0][0]
        called_kwargs = mock_post.call_args[1]
        assert called_url == "https://embeddings.example.com/v1/embeddings"
        assert called_kwargs["headers"]["Authorization"] == "Bearer dynamic-token"
        # Provider prefix stripped: model sent as the bare name.
        assert called_kwargs["json"]["model"] == "mock-model"
        assert called_kwargs["json"]["input"] == ["hi"]

    @patch("httpx.post")
    def test_encode_uses_static_api_key_when_no_provider(self, mock_post):
        mock_post.return_value = self._mock_response([[0.1, 0.2]])

        client = LiteLLMClient(
            model_name="openai/mock-model",
            api_key="sk-static",
            api_base="https://embeddings.example.com/v1",
            embedding_dimension=2,
            response_format="raw_array",
        )
        client.encode(["hi"])

        assert mock_post.call_args[1]["headers"]["Authorization"] == "Bearer sk-static"

    def test_encode_raises_without_api_base(self):
        client = LiteLLMClient(
            model_name="openai/mock-model",
            embedding_dimension=2,
            response_format="raw_array",
        )
        with pytest.raises(RuntimeError, match="requires EMBEDDINGS_API_BASE"):
            client.encode(["hi"])

    @patch("httpx.post")
    def test_encode_wraps_http_status_error(self, mock_post):
        response = MagicMock()
        response.status_code = 401
        response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "unauthorized", request=MagicMock(), response=response
        )
        mock_post.return_value = response

        client = LiteLLMClient(
            model_name="openai/mock-model",
            api_base="https://embeddings.example.com/v1",
            embedding_dimension=2,
            response_format="raw_array",
        )
        with pytest.raises(RuntimeError, match="status 401"):
            client.encode(["hi"])


class TestOpenAIHttpEncode:
    """Tests for direct OpenAI-compatible HTTP embedding calls."""

    @patch("httpx.post")
    def test_encode_preserves_model_alias_and_reads_envelope(self, mock_post):
        response = MagicMock()
        response.json.return_value = {"data": [{"embedding": [0.1, 0.2]}]}
        response.raise_for_status.return_value = None
        mock_post.return_value = response

        client = LiteLLMClient(
            model_name="voyage/voyage-3",
            api_key="sk-static",
            api_base="https://embeddings.example.com/v1",
            embedding_dimension=2,
            response_format="openai_http",
        )
        result = client.encode(["hello"])

        assert result.shape == (1, 2)
        assert mock_post.call_args[0][0] == "https://embeddings.example.com/v1/embeddings"
        assert mock_post.call_args[1]["json"]["model"] == "voyage/voyage-3"
        assert mock_post.call_args[1]["json"]["input"] == ["hello"]
        assert mock_post.call_args[1]["headers"]["Authorization"] == "Bearer sk-static"


class TestFactoryResponseFormat:
    """The factory forwards response_format to LiteLLMClient."""

    def test_factory_passes_response_format(self):
        client = create_embeddings_client(
            provider="litellm",
            model_name="openai/mock-model",
            api_base="https://embeddings.example.com/v1",
            embedding_dimension=2,
            response_format="raw_array",
        )
        assert isinstance(client, LiteLLMClient)
        assert client.response_format == "raw_array"

    def test_factory_defaults_to_openai(self):
        client = create_embeddings_client(
            provider="litellm",
            model_name="openai/mock-model",
            embedding_dimension=2,
        )
        assert client.response_format == "openai"

    def test_factory_passes_openai_http_response_format(self):
        client = create_embeddings_client(
            provider="litellm",
            model_name="voyage/voyage-3",
            api_base="https://embeddings.example.com/v1",
            embedding_dimension=2,
            response_format="openai_http",
        )
        assert isinstance(client, LiteLLMClient)
        assert client.response_format == "openai_http"
