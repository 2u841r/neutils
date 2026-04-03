# urlencode

Percent-encode a string for use in URLs.

## Usage

```
urlencode <str>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `str` | String to encode |

## Examples

```bash
# Encode a query value
urlencode "hello world"
# hello%20world

# Encode special characters
urlencode "price=10&currency=€"
# price%3D10%26currency%3D%E2%82%AC
```
