const fs = require("fs");
const path = require("path");

const contracts = ["Factory", "Pair", "Router"];

if (!fs.existsSync("./abis")) {
  fs.mkdirSync("./abis");
}

contracts.forEach((name) => {
  const filePath = path.resolve(
    __dirname,
    `../artifacts/contracts/${name}.sol/${name}.json`
  );

  if (!fs.existsSync(filePath)) {
    console.log(`❌ Missing artifact: ${name}`);
    return;
  }

  const contract = require(filePath);

  fs.writeFileSync(
    `./abis/${name}.abi`,
    JSON.stringify(contract.abi, null, 2)
  );

  console.log(`✅ Exported ${name}`);
});