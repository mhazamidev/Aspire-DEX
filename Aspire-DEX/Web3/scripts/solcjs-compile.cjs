const fs = require("fs");
const path = require("path");
const solc = require("solc");

const CONTRACTS_DIR = path.resolve(__dirname, "../contracts");

function findSolFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) findSolFiles(full, out);
    else if (entry.name.endsWith(".sol")) out.push(full);
  }
  return out;
}

const sources = {};
for (const file of findSolFiles(CONTRACTS_DIR)) {
  const rel = "contracts/" + path.relative(CONTRACTS_DIR, file).replace(/\\/g, "/");
  sources[rel] = { content: fs.readFileSync(file, "utf8") };
}

function findImports(importPath) {
  const candidates = [
    path.resolve(__dirname, "..", importPath),
    path.resolve(__dirname, "../node_modules", importPath),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return { contents: fs.readFileSync(candidate, "utf8") };
    }
  }
  return { error: `File not found: ${importPath}` };
}

const input = {
  language: "Solidity",
  sources,
  settings: {
    viaIR: true,
    optimizer: { enabled: true, runs: 200 },
    outputSelection: {
      "*": { "*": ["abi", "evm.bytecode.object"] },
    },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));

let hasError = false;
if (output.errors) {
  for (const err of output.errors) {
    if (err.severity === "error") hasError = true;
    console.log(`[${err.severity}] ${err.formattedMessage}`);
  }
}

if (!hasError) {
  console.log("\n✅ Compiled successfully, no errors.");
  fs.mkdirSync(path.resolve(__dirname, "../artifacts-solcjs"), { recursive: true });
  fs.writeFileSync(
    path.resolve(__dirname, "../artifacts-solcjs/output.json"),
    JSON.stringify(output, null, 2)
  );
} else {
  console.log("\n❌ Compilation failed.");
  process.exit(1);
}
