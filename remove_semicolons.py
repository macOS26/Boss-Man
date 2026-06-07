#!/usr/bin/env python3
"""Remove statement-separator semicolons from Swift files.
Splits lines like `stmt1; stmt2` into separate lines.
Preserves semicolons inside string literals and comments.
"""

import re
import os
import sys


def mask_strings(line):
    """Replace string literals with placeholders, return (masked, replacements)."""
    replacements = {}
    counter = [0]
    result = []
    i = 0
    while i < len(line):
        if line[i] == '"':
            # Find end of string (handle escapes)
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
    """Restore placeholders back to original strings."""
    for key, value in replacements.items():
        line = line.replace(key, value)
    return line


def find_code_semicolons(line):
    """Find indices of semicolons that are statement separators (not in strings/comments)."""
    masked, replacements = mask_strings(line)

    # Find comment position
    comment_start = None
    for i, ch in enumerate(masked):
        if ch == '/' and i + 1 < len(masked) and masked[i + 1] == '/':
            comment_start = i
            break

    positions = []
    for i, ch in enumerate(masked):
        if ch == ';':
            if comment_start is not None and i >= comment_start:
                continue
            # Check not inside a placeholder
            in_placeholder = False
            for key in replacements:
                start = masked.find(key, max(0, i - 50))
                if start != -1 and start <= i < start + len(key):
                    in_placeholder = True
                    break
            if not in_placeholder:
                positions.append(i)

    return positions


def split_semicolons(line, indent_str):
    """Split a line at statement-separator semicolons.

    Returns a list of (indent, content) tuples.
    """
    masked, replacements = mask_strings(line)

    # Find comment position in masked line
    comment_start = None
    for i, ch in enumerate(masked):
        if ch == '/' and i + 1 < len(masked) and masked[i + 1] == '/':
            comment_start = i
            break

    # Extract comment if present
    comment = ''
    if comment_start is not None:
        comment = unmask(masked[comment_start:], replacements)
        masked = masked[:comment_start].rstrip()

    # Split masked line at semicolons (respecting brace depth)
    parts = []
    current = ''
    brace_depth = 0
    paren_depth = 0
    bracket_depth = 0
    i = 0

    while i < len(masked):
        ch = masked[i]

        # Check for placeholder
        if ch == '_' and i + 1 < len(masked):
            placeholder_found = None
            for key in replacements:
                if masked[i:i+len(key)] == key:
                    placeholder_found = key
                    break
            if placeholder_found:
                current += placeholder_found
                i += len(placeholder_found)
                continue

        if ch == '{':
            brace_depth += 1
            current += ch
        elif ch == '}':
            brace_depth -= 1
            current += ch
        elif ch == '(':
            paren_depth += 1
            current += ch
        elif ch == ')':
            paren_depth -= 1
            current += ch
        elif ch == '[':
            bracket_depth += 1
            current += ch
        elif ch == ']':
            bracket_depth -= 1
            current += ch
        elif ch == ';' and brace_depth == 0 and paren_depth == 0 and bracket_depth == 0:
            # Statement separator at top level
            part = current.strip()
            if part:
                parts.append(part)
            current = ''
        else:
            current += ch
        i += 1

    # Add remaining
    part = current.strip()
    if part:
        parts.append(part)

    # Unmask strings in each part
    parts = [unmask(p, replacements) for p in parts]

    return parts, comment


def process_line(line, base_indent):
    """Process a single line, splitting at semicolons if needed.

    Returns list of lines (strings with newlines).
    """
    positions = find_code_semicolons(line)

    if not positions:
        return [line]

    parts, comment = split_semicolons(line, base_indent)

    if len(parts) <= 1:
        # No statement-separator semicolons (maybe semicolons were all in strings)
        return [line]

    # Build result lines
    result = []
    for i, part in enumerate(parts):
        if i == 0:
            result_line = base_indent + part
        else:
            result_line = base_indent + part

        # Attach comment to last line
        if i == len(parts) - 1 and comment:
            result_line += '  ' + comment

        result.append(result_line + '\n')

    return result


def process_file(filepath):
    """Process a Swift file, removing statement-separator semicolons."""
    with open(filepath, 'r') as f:
        content = f.read()

    lines = content.split('\n')
    new_lines = []
    changed = False

    for line in lines:
        # Get the original line without trailing newline
        original = line.rstrip('\n')

        # Get indentation
        indent_match = re.match(r'^(\s*)', original)
        base_indent = indent_match.group(1) if indent_match else ''

        # Check if this line has statement-separator semicolons
        positions = find_code_semicolons(original)

        if not positions:
            new_lines.append(original)
            continue

        # Process the line
        result = process_line(original + '\n', base_indent)

        # Check if anything changed
        if len(result) > 1 or (len(result) == 1 and result[0].rstrip('\n') != original):
            changed = True
            for r in result:
                new_lines.append(r.rstrip('\n'))
        else:
            new_lines.append(original)

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