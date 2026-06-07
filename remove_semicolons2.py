#!/usr/bin/env python3
"""Remove ALL statement-separator semicolons from Swift files.
Handles semicolons inside braces, guard clauses, case statements, etc.
"""

import re
import os


def mask_strings(line):
    """Replace string literals with placeholders."""
    replacements = {}
    counter = [0]
    result = []
    i = 0
    while i < len(line):
        if line[i] == '"':
            j = i + 1
            while j < len(line):
                if line[j] == '\\' and j + 1 < len(line):
                    j += 2
                elif line[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            s = line[i:j]
            key = f"__STR{counter[0]}__"
            counter[0] += 1
            replacements[key] = s
            result.append(key)
            i = j
        else:
            result.append(line[i])
            i += 1
    return ''.join(result), replacements


def unmask(line, replacements):
    for key, value in replacements.items():
        line = line.replace(key, value)
    return line


def find_code_semicolons(line):
    """Find indices of semicolons that are in code (not strings/comments)."""
    masked, replacements = mask_strings(line)

    # Find comment position
    comment_start = None
    for i in range(len(masked) - 1):
        if masked[i] == '/' and masked[i + 1] == '/':
            in_p = False
            for k in replacements:
                pos = masked.find(k, max(0, i - 50))
                if pos != -1 and pos <= i < pos + len(k):
                    in_p = True
                    break
            if not in_p:
                comment_start = i
                break

    positions = []
    for i, ch in enumerate(masked):
        if ch == ';':
            if comment_start is not None and i >= comment_start:
                continue
            in_placeholder = False
            for key in replacements:
                pos = masked.find(key, max(0, i - 50))
                if pos != -1 and pos <= i < pos + len(key):
                    in_placeholder = True
                    break
            if not in_placeholder:
                positions.append(i)

    return positions


def has_code_semicolon(line):
    """Check if a line has statement-separator semicolons in code."""
    return len(find_code_semicolons(line)) > 0


def process_file(filepath):
    """Process a Swift file, removing all statement-separator semicolons."""
    with open(filepath, 'r') as f:
        content = f.read()

    lines = content.split('\n')
    new_lines = []
    changed = False

    for line in lines:
        if not has_code_semicolon(line):
            new_lines.append(line)
            continue

        changed = True
        masked, replacements = mask_strings(line)

        # Find comment position in masked line
        comment_start = None
        for i in range(len(masked) - 1):
            if masked[i] == '/' and masked[i + 1] == '/':
                in_p = False
                for k in replacements:
                    pos = masked.find(k, max(0, i - 50))
                    if pos != -1 and pos <= i < pos + len(k):
                        in_p = True
                        break
                if not in_p:
                    comment_start = i
                    break

        # Extract comment
        comment = ''
        code_part = line
        if comment_start is not None:
            comment = unmask(masked[comment_start:], replacements)
            code_part = line[:len(line) - len(line) + comment_start].rstrip()

        # Get the base indent
        indent_match = re.match(r'^(\s*)', line)
        base_indent = indent_match.group(1) if indent_match else ''

        # Re-mask the code part for safe splitting
        code_masked, code_replacements = mask_strings(line)
        if comment_start is not None:
            code_masked = code_masked[:comment_start].rstrip()

        # Split at semicolons respecting brace/paren/bracket depth
        # But we need to handle the case where semicolons are inside braces
        # like: if cond { stmt1; stmt2 }
        # We want to split those too.

        # Strategy: split at ALL code semicolons regardless of brace depth
        parts = []
        current = ''
        i = 0
        while i < len(code_masked):
            ch = code_masked[i]

            # Check for placeholder
            if ch == '_' and i + 1 < len(code_masked):
                placeholder_found = None
                for key in code_replacements:
                    if code_masked[i:i+len(key)] == key:
                        placeholder_found = key
                        break
                if placeholder_found:
                    current += placeholder_found
                    i += len(placeholder_found)
                    continue

            if ch == ';':
                part = current.strip()
                if part:
                    parts.append(part)
                current = ''
            else:
                current += ch
            i += 1

        part = current.strip()
        if part:
            parts.append(part)

        # Unmask strings in each part
        parts = [unmask(p, code_replacements) for p in parts]

        if len(parts) <= 1:
            # No actual splits happened (semicolons were all in strings)
            new_lines.append(line)
            changed = False
            continue

        # Build result lines
        # Each part gets the same indentation as the original line
        for j, part in enumerate(parts):
            result_line = base_indent + part
            # Attach comment to last line
            if j == len(parts) - 1 and comment:
                result_line += '  ' + comment
            new_lines.append(result_line)

    if changed:
        with open(filepath, 'w') as f:
            f.write('\n'.join(new_lines))
            if content.endswith('\n'):
                f.write('\n')
        return True
    return False


def main():
    root = '/Users/toddbruss/Documents/GitHub/BossMan'

    dirs = [
        os.path.join(root, 'boss-man-spritekit-swift/Boss-Man'),
        os.path.join(root, 'boss-man-spritekit-web/Sources/BossMan'),
        os.path.join(root, 'boss-man-spritekit-desktop/Sources/BossManDesktop'),
        os.path.join(root, 'wasm-web-kit/spritekit/Sources'),
        os.path.join(root, 'scripts'),
    ]

    modified = 0
    for d in dirs:
        if not os.path.exists(d):
            continue
        for dirpath, dirnames, filenames in os.walk(d):
            for fn in filenames:
                if fn.endswith('.swift'):
                    filepath = os.path.join(dirpath, fn)
                    if process_file(filepath):
                        print(f'  Modified: {filepath}')
                        modified += 1

    print(f'\nTotal files modified: {modified}')


if __name__ == '__main__':
    main()