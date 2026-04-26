import re

path = r'frontend\lib\screens\intelligence\threat_intelligence_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the _worldBounds field + its comment using regex
pattern = r'\n\s*//[^\n]*world bounds[^\n]*\n\s*static final LatLngBounds _worldBounds[^;]+;'
new_comment = '\n  // World zoom/pan is clamped by onPositionChanged; no static bounds needed.'
content, n = re.subn(pattern, new_comment, content, flags=re.DOTALL)
print(f'_worldBounds removal: {n} match(es)')

# Also remove the LatLngBounds import if it only came from flutter_map
# (It might still be used elsewhere, so we check first)
if '_worldBounds' in content:
    print('WARNING: _worldBounds still referenced somewhere!')
else:
    print('_worldBounds fully removed.')

# Check if LatLngBounds is still used anywhere
usages = content.count('LatLngBounds')
print(f'LatLngBounds usages remaining: {usages}')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done.')
