# mbox-diff

Find new emails between two mbox files by comparing Message-IDs.

![mbox-diff demo](demo/demo.gif)

## Usage

```
mbox-diff [OPTIONS] <base_mbox> <new_mbox>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `base_mbox` | Base mbox file (emails to exclude) |
| `new_mbox` | New mbox file (emails to diff against base) |

## Options

| Option | Short | Description |
|--------|-------|-------------|
| `--output` | `-o` | Output mbox file path (required) |

## Examples

```bash
# Write new emails to a file
mbox-diff base.mbox new.mbox -o diff.mbox

# Sync a mailbox incrementally
mbox-diff yesterday.mbox today.mbox -o new-messages.mbox
```
