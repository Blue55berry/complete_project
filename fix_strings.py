import sys

path = r'frontend\lib\screens\intelligence\threat_intelligence_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
out = []
fixes = 0

BULLET = '\u2022'
MDASH  = '\u2014'
NDASH  = '\u2013'
DEG    = '\u00b0'
CHECK  = '\u2713'
CLIP   = '\U0001F4CE'

for line in lines:
    orig = line

    # Detect corrupt: line has high ratio of non-ASCII junk characters (> U+0590)
    def is_corrupt(s):
        junk = sum(1 for c in s if ord(c) > 0x02FF and ord(c) < 0xE000)
        return junk > 3

    # Fix mediaName chip label
    if 'threat.mediaName' in line and is_corrupt(line):
        line = "                      '" + CLIP + " ${threat.mediaName}  " + BULLET + "  ${threat.score}%',"
        fixes += 1

    # Fix region/city label — two-line case, take first part
    elif 'threat.region' in line and 'cityOrZone' not in line and is_corrupt(line) and 'threat.' in line:
        line = "                    '${threat.region} " + BULLET + " ${threat.cityOrZoneLabel}',"
        fixes += 1

    # Fix region/city label — second-line case
    elif 'cityOrZoneLabel' in line and 'threat.region' not in line and is_corrupt(line):
        # Skip this line; previous line was already corrected to include it
        line = ''
        fixes += 1

    # Fix BLOCKCHAIN label
    elif 'BLOCKCHAIN' in line and is_corrupt(line):
        line = "                      '" + CHECK + " BLOCKCHAIN',"
        fixes += 1

    # Fix Video frame analysis label
    elif 'Video frame analysis' in line and is_corrupt(line):
        line = "            'Video frame analysis " + BULLET + " ${threat.score}%',"
        fixes += 1

    # Fix Image analysis label
    elif 'Image analysis' in line and 'threat.score' in line and is_corrupt(line):
        line = "            'Image analysis " + BULLET + " ${threat.score}%',"
        fixes += 1

    # Fix _Ring t comment
    elif '0..1' in line and 'how far' in line and is_corrupt(line):
        line = '  final double t; // 0..1 ' + NDASH + ' how far expanded this ring is'
        fixes += 1

    # Fix [t] animation clock comment
    elif '[t] is the' in line and is_corrupt(line):
        line = '/// [t] is the normalised animation clock (0.0 ' + NDASH + ' 1.0), driven by parent'
        fixes += 1

    # Fix N90 degree
    elif "'N90" in line and is_corrupt(line):
        line = "        text: 'N90" + DEG + "',"
        fixes += 1

    # Fix E180 degree
    elif "'E180" in line and is_corrupt(line):
        line = "        text: 'E180" + DEG + "',"
        fixes += 1

    # Fix any remaining comment-only lines still corrupt
    elif line.strip().startswith('//') and is_corrupt(line):
        indent = len(line) - len(line.lstrip())
        line = ' ' * indent + '// ---------------------------------------------------'
        fixes += 1

    out.append(line)

content = '\n'.join(out)

# Global replacements for any remaining encoded dashes in comments
content = content.replace('â\x80\x94', MDASH)
content = content.replace('\u00e2\u0080\u0094', MDASH)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Fixes applied: ' + str(fixes))
