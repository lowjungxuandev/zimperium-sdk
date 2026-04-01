# Requesting a zKeyBox or zDefend SDK Package

Use this Web API call to start building a customized `zKeyBox` or `zDefend` SDK package on the server.

The package is not returned immediately. Once the build finishes, you can download one or more generated files using the request ID returned by this call.

Build generation may take several hours.

## Endpoint

```text
POST /api/request?product=(secure_key_box|zkeybox|zdefend)&expires=<expiration time>&token=<API token>&signature=<request signature>
```

`product` identifies the package type to build.

For details about `expires`, `token`, and `signature`, refer to the mandatory request URI parameter documentation.

## HTTP Method

```text
POST
```

## POST Data

Send the following form fields:

| Field | Type | Description |
| --- | --- | --- |
| `version` | String | The product version to build. Use the product version list API to see available versions. |
| `config` | JSON string | The package configuration. You can use the **See JSON Data** button in the package request form to generate a starting config and then adjust it if needed. |

## Standard zDefend Request

To request the standard, non-custom `zDefend` SDK package, use:

```json
{ "request_type": 1 }
```

If you need help constructing the `config` value, contact Zimperium.

Some configuration values are version-specific and may change over time.

## Success Response

On success, the server returns:

```json
{ "request_id": "<request ID>" }
```

`request_id` identifies the package build request. Use it later to check request status and download the generated package when the build is complete.

## cURL Example

```bash
curl -X POST \
  -d "version=5.26.1" \
  -d 'config={"request_type":1}' \
  "https://devportal.zimperium.com/api/request?product=secure_key_box&token=abcdefgh12345678&expires=1600000000&signature=b3228aa39f45f57a9c0ae88a4f4414069c1b35b70f24e0f513d0902e452389f1"
```

## Flow Summary

1. Send a signed `POST` request to `/api/request`.
2. Save the returned `request_id`.
3. Wait for the package build to finish.
4. Query the request by ID.
5. Download the generated package file(s).
