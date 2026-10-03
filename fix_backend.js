const fs = require('fs');
const serverPath = '../backend/server.js';
let c = fs.readFileSync(serverPath, 'utf8');

// Find and replace using line-based approach
const lines = c.split('\n');
let fixStart = -1;
let fixEnd = -1;

for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("dispatch.status !== 'available'") && lines[i+1] && lines[i+1].includes('REQUEST ALREADY TAKEN')) {
    fixStart = i;
    fixEnd = i + 2; // covers the if block: if(...){ return ...; }
    break;
  }
}

if (fixStart === -1) {
  console.log('Pattern not found. Lines around REQUEST ALREADY TAKEN:');
  lines.forEach((l, i) => { if (l.includes('REQUEST ALREADY TAKEN')) console.log(i+1, JSON.stringify(l)); });
} else {
  console.log('Found at lines', fixStart+1, 'to', fixEnd+1);
  console.log('Replacing:', lines.slice(fixStart, fixEnd+1).join('\n'));
  
  const replacement = [
    lines[fixStart], // keep: if (dispatch.status !== 'available') {
    "    // If THIS same driver already accepted it, return the existing trip so the app navigates correctly.",
    "    const driverRow = await dbGet('SELECT * FROM users WHERE driver_id = ? AND vehicle_no = ?', [driver_id, vehicle_no]);",
    "    if (driverRow) {",
    "      const existingTrip = await dbGet(",
    "        \"SELECT * FROM emergency_trips WHERE dispatch_id = ? AND driver_id = ? AND status IN ('en_route','arrived') ORDER BY started_at DESC LIMIT 1\",",
    "        [dispatchId, driverRow.id]",
    "      );",
    "      if (existingTrip) return res.status(200).json(existingTrip);",
    "    }",
    lines[fixStart+1], // keep: return res.status(409).json(...)
    lines[fixEnd],    // keep: }
  ];
  
  lines.splice(fixStart, fixEnd - fixStart + 1, ...replacement);
  fs.writeFileSync(serverPath, lines.join('\n'));
  console.log('Backend fixed successfully!');
}
