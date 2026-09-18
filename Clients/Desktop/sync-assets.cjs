const path = require('node:path');
const fs = require('node:fs');
// Build from the same brand asset as Mac; do not maintain a divergent copy.
fs.copyFileSync(path.join(__dirname, '../../Resources/Brand/QLogo.png'), path.join(__dirname, 'ui/QLogo.png'));
