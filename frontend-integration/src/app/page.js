'use client';

import Image from "next/image";
import { ethers } from "ethers";
import { useEffect, useState } from "react"

/* -------------------------- helpers -------------------------- */
function formatAddress(addr) {
  if (!addr) return '';
  return `${addr.slice(0, 6)}…${addr.slice(-6)}`;
}


export default function Home() {
  const ENGINE_CONTRACT_ADDRESS = "0xdb1b8fc2a20f7b85cf7571a6fefd74124ddde037";
  const STABLECOIN_CONTRACT_ADDRESS = "0xbddf447bc2cadac318b97d47b37589235b48d8bc";
  const WETH_ADDRESS = "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9";

  const PUBLIC_PROVIDER = "https://eth-sepolia.g.alchemy.com/v2/2ef7uiLLqGeZqzXmhWIPu";
  const ABI = [
    // ===== Core Actions =====
    "function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)",
    "function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToMint)",
    "function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)",
    "function burnDsc(uint256 amount)",
    "function burnDscAndRedeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)",
    "function mintDsc(uint256 amount)",
    "function liquidate(address collateral, address user, uint256 debtToCover)",

    // ===== Getters / Views =====
    "function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) view returns (uint256)",
    "function getAccountCollateralValue(address user) view returns (uint256)",
    "function getAccountInformation(address user) view returns (uint256 totalDscMinted, uint256 collateralValueInUsd)",
    "function getCollateralDeposited(address user, address token) view returns (uint256)",
    "function getCollateralTokens() view returns (address[])",
    "function getDSCMinted(address user) view returns (uint256)",
    "function getHealthFactor(address user) view returns (uint256)",
    "function getLiquidationThreshold() view returns (uint256)",
    "function getMinHealthFactor() view returns (uint256)",
    "function getPrecision() view returns (uint256)",
    "function getPriceFeed(address token) view returns (address)",
    "function getTokenAmountFromDSC(address token, uint256 dscAmount) view returns (uint256)",
    "function getUSDValue(address token, uint256 amount) view returns (uint256)",

    // ===== Events =====
    "event CollateralDeposited(address indexed user, address indexed token, uint256 amount)",
    "event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount)",
    "event DSCMinted(address indexed user, uint256 amountDSCMinted)",
    "event DSCBurned(uint256 amountDSCToBurn, address indexed dscFrom, address indexed onBehalfOf)"
  ]

  const STABLECOIN_ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function balanceOf(address owner) view returns (uint256)",
    "function transfer(address to, uint256 amount) returns (bool)",
    "function approve(address spender, uint256 amount) returns (bool)"
  ];


  const [dsceContract, setDsceContract] = useState(null);
  const [dscContract, setDscContract] = useState(null);
  const [userAddress, setUserAddress] = useState(null);
  const [collateralAmount, setCollateralAmount] = useState("");
  const [mintAmount, setMintAmount] = useState("");
  const [maxMintable, setMaxMintable] = useState("");
  const [adjustedCollateral, setAdjustedCollateral] = useState("");
  const [ethUsdPrice, setEthUsdPrice] = useState(null);
  const [signer, setSigner] = useState(null);
  const [userStats, setUserStats] = useState(null);
  const [redeemAmount, setRedeemAmount] = useState("");
  const [burnAmount, setBurnAmount] = useState("");
  const [projectedHF, setProjectedHF] = useState(null);
  const [targetAddress, setTargetAddress] = useState("");
  const [targetStats, setTargetStats] = useState(null);
  const [liquidateAmount, setLiquidateAmount] = useState("");
  const [liquidationPreview, setLiquidationPreview] = useState(null);



  const connectWallet = async () => {
    if (typeof window.ethereum === "undefined") {
      alert("MetaMask not found! Please install it.");
      return;
    }

    try {
      const provider = new ethers.BrowserProvider(window.ethereum); //so can talk to the blockchain
      await provider.send("eth_requestAccounts", []); // popup ask user to connect

      const signer = await provider.getSigner(); //Represents the connected wallet, used to sign transactions.
      const address = await signer.getAddress(); //get user wallet address
      setUserAddress(address);
      setSigner(signer);

      // save contracts in state
      // const dsce = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      // const dsc = new ethers.Contract(STABLECOIN_CONTRACT_ADDRESS, ABI, signer);
      const dsce = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const dsc = new ethers.Contract(STABLECOIN_CONTRACT_ADDRESS, ABI, signer);

      setDsceContract(dsce);
      setDscContract(dsc);

      await fetchUserStats(dsce, address);

    } catch (err) {
      console.error("Wallet connection failed:", err);
    }
  }

  const fetchUserStats = async (contract = dsceContract, user = userAddress) => {
    if (!contract || !user) return;

    try {
      console.log("Fetching stats for", user);
      const [totalDscMinted, collateralValueInUsd] =
        await contract.getAccountInformation(user);
      console.log("getAccountInformation result:", totalDscMinted);


      const collateralDeposited = await contract.getCollateralDeposited(user, WETH_ADDRESS);
      const healthFactor = await contract.getHealthFactor(user);

      setUserStats({
        dscMinted: ethers.formatUnits(totalDscMinted, 18),
        collateralUsd: ethers.formatUnits(collateralValueInUsd, 18),
        collateralDeposited: ethers.formatUnits(collateralDeposited, 18),
        healthFactor: ethers.formatUnits(healthFactor, 18),
      });
    } catch (err) {
      console.error("Failed to fetch stats:", err);
    }
  };




  const handleInputCollateralChange = async (e) => {
    const value = e.target.value;
    setCollateralAmount(value);

    if (!dsceContract || !value) return;

    try {
      // call contract for USD value
      const usdValue = await dsceContract.getUSDValue(WETH_ADDRESS, ethers.parseUnits(value, 18));
      setEthUsdPrice(ethers.formatUnits(usdValue, 18));


      // apply protocol rule (e.g. divide by 2 for 200% collateralization)
      const max = (usdValue * 80n) / 100n; // bigint math, applting to 80% liquidation threshold
      setMaxMintable(ethers.formatUnits(max, 18));

    } catch (err) {
      console.error("Failed to calculate mintable:", err);
    }
  };

  //Each transaction (swap deposit() → approve() → depositCollateralAndMintDsc()) is a separate on-chain call, so MetaMask asks you to confirm all three.
  const handleDepositAndMint = async () => {
    try {
      if (!dsceContract || !signer) return;

      const collateral = ethers.parseUnits(collateralAmount, 18); // user input
      const dscToMint = ethers.parseUnits(mintAmount, 18);

      // Step 1: Wrap ETH into WETH
      const weth = new ethers.Contract(
        WETH_ADDRESS,
        ["function deposit() payable", "function approve(address spender, uint256 amount) public returns (bool)"],
        signer
      );
      const tx1 = await weth.deposit({ value: collateral }); // wrap same amount of ETH
      await tx1.wait();

      // Step 2: Approve WETH for DSCEngine
      const tx2 = await weth.approve(ENGINE_CONTRACT_ADDRESS, collateral);
      await tx2.wait();


      // Step 3: Deposit & Mint in DSCEngine
      const tx3 = await dsceContract.depositCollateralAndMintDsc(
        WETH_ADDRESS,
        collateral,
        dscToMint
      );
      await tx3.wait();
      await fetchUserStats(dsceContract, userAddress);

      alert("Deposit + Wrap + Mint successful ✅");
    } catch (err) {
      console.error("Deposit & Mint failed:", err);
      alert("Transaction failed ❌");
    }
  };

  // Burn DSC
  // const handleBurnDsc = async () => {
  //   try {
  //     if (!dsceContract || !dscContract || !signer) return;

  //     const amount = ethers.parseUnits(burnAmount, 18); // user input
  //     // approve DSCEngine to take DSC
  //     const tx1 = await dscContract.approve(ENGINE_CONTRACT_ADDRESS, amount);
  //     await tx1.wait();

  //     // call burn
  //     const tx2 = await dsceContract.burnDsc(amount);
  //     await tx2.wait();

  //     alert("DSC burned successfully ✅");
  //     await fetchUserStats();
  //   } catch (err) {
  //     console.error("Burn failed:", err);
  //     alert("Burn failed ❌");
  //   }
  // };

  const handleBurnDsc = async () => {
    try {
      if (!signer) return alert("Connect your wallet first");

      // Build fresh instances from the current signer (defensive)
      const engine = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const dscErc20 = new ethers.Contract(
        STABLECOIN_CONTRACT_ADDRESS,
        STABLECOIN_ABI,
        signer
      );

      // Parse amount and optional client-side check
      const amount = ethers.parseUnits(burnAmount || "0", 18);
      if (amount === 0n) return alert("Enter an amount to burn");

      // (optional) make sure user has enough DSC
      const bal = await dscErc20.balanceOf(await signer.getAddress());
      if (bal < amount) return alert("Not enough DSC to burn");

      // 1) approve engine to pull the DSC
      const tx1 = await dscErc20.approve(ENGINE_CONTRACT_ADDRESS, amount);
      await tx1.wait();

      // 2) call engine.burnDsc
      const tx2 = await engine.burnDsc(amount);
      await tx2.wait();

      alert("DSC burned successfully ✅");
      await fetchUserStats(engine, await signer.getAddress());
    } catch (err) {
      console.error("Burn failed:", err);
      alert("Burn failed ❌ (check console)");
    }
  };


  const handleRedeemInputChange = async (e) => {
    const value = e.target.value;
    setRedeemAmount(value);

    if (!dsceContract || !userStats || !value) return;

    try {
      // Convert WETH amount to USD
      const usdValue = await dsceContract.getUSDValue(
        WETH_ADDRESS,
        ethers.parseUnits(value, 18)
      );

      // new collateral value after redeem
      const newCollateralValue = BigInt(
        ethers.parseUnits(userStats.collateralUsd, 18)
      ) - usdValue;

      // calculate new health factor
      const newHF = await dsceContract.calculateHealthFactor(
        ethers.parseUnits(userStats.dscMinted, 18),
        newCollateralValue
      );

      setProjectedHF(Number(ethers.formatUnits(newHF, 18)).toFixed(2));
    } catch (err) {
      console.error("Failed to calculate projected HF:", err);
      setProjectedHF(null);
    }
  };


  // Redeem Collateral

  const handleRedeemCollateral = async () => {
    try {
      if (!dsceContract || !signer) return;

      const amount = ethers.parseUnits(redeemAmount, 18);

      const tx = await dsceContract.redeemCollateral(WETH_ADDRESS, amount);
      await tx.wait();
      alert("Redeem successful ✅");
      await fetchUserStats(dsceContract, userAddress);
    } catch (err) {
      console.error("Redeem failed:", err);
      // alert("Redeem failed ❌");
    }
  };


  // fetch target user stats
  const fetchTargetUserStats = async (addr) => {
    if (!dsceContract || !addr) return;
    try {
      const [totalDscMinted, collateralValueInUsd] =
        await dsceContract.getAccountInformation(addr);

      const healthFactor = await dsceContract.getHealthFactor(addr);

      setTargetStats({
        dscMinted: ethers.formatUnits(totalDscMinted, 18),
        collateralUsd: ethers.formatUnits(collateralValueInUsd, 18),
        healthFactor: ethers.formatUnits(healthFactor, 18),
      });
    } catch (err) {
      console.error("Failed to fetch target stats:", err);
      setTargetStats(null);
    }
  };


  // const handleLiquidateInputChange = async (value) => {
  //   if (!dsceContract || !value || !targetStats) return;

  //   try {
  //     // const dscAmount = ethers.parseUnits(value, 18);

  //     const inputAmount = ethers.parseUnits(value, 18);
  //     const targetDebt = ethers.parseUnits(targetStats.dscMinted, 18);

  //     // 👇 Clamp to target’s actual debt
  //     const dscAmount = inputAmount > targetDebt ? targetDebt : inputAmount;

  //     // 1️⃣ Base and bonus collateral the liquidator will receive
  //     const baseCollateral = await dsceContract.getTokenAmountFromDSC(WETH_ADDRESS, dscAmount);
  //     const bonusCollateral = (baseCollateral * 10n) / 100n;
  //     const totalCollateral = baseCollateral + bonusCollateral;

  //     // 2️⃣ USD value of total collateral taken
  //     const usdValue = await dsceContract.getUSDValue(WETH_ADDRESS, totalCollateral);

  //     // 3️⃣ Compute target’s projected HF after liquidation
  //     const targetMinted = ethers.parseUnits(targetStats.dscMinted, 18);
  //     const targetCollateralUsd = ethers.parseUnits(targetStats.collateralUsd, 18);

  //     const newTargetMinted = targetMinted - dscAmount;
  //     const newTargetCollateralUsd = targetCollateralUsd - usdValue;

  //     const newTargetHF = await dsceContract.calculateHealthFactor(
  //       newTargetMinted,
  //       newTargetCollateralUsd
  //     );

  //     // 4️⃣ Update UI preview
  //     setLiquidationPreview({
  //       base: ethers.formatUnits(baseCollateral, 18),
  //       bonus: ethers.formatUnits(bonusCollateral, 18),
  //       total: ethers.formatUnits(totalCollateral, 18),
  //       usd: ethers.formatUnits(usdValue, 18),
  //       targetProjectedHF: Number(ethers.formatUnits(newTargetHF, 18)).toFixed(2),
  //     });
  //   } catch (err) {
  //     console.error("Failed to preview liquidation:", err);
  //     setLiquidationPreview(null);
  //   }
  // };

  // const handleLiquidateInputChange = async (value) => {
  //   if (!dsceContract || !value || !targetAddress || !targetStats) return;

  //   try {
  //     const inputAmount = Number(value);
  //     const targetDebt = Number(targetStats.dscMinted);

  //     // Clamp to target’s actual DSC debt
  //     if (inputAmount > targetDebt) {
  //       setLiquidateAmount(targetDebt.toString());
  //     } else {
  //       setLiquidateAmount(value);
  //     }

  //     const dscAmount = ethers.parseUnits(
  //       inputAmount > targetDebt ? targetDebt.toString() : value,
  //       18
  //     );

  //     // 1️⃣ Base + bonus collateral to receive
  //     const baseCollateral = await dsceContract.getTokenAmountFromDSC(WETH_ADDRESS, dscAmount);
  //     const bonusCollateral = (baseCollateral * 10n) / 100n;
  //     const totalCollateral = baseCollateral + bonusCollateral;
  //     const usdValue = await dsceContract.getUSDValue(WETH_ADDRESS, totalCollateral);

  //     // 2️⃣ Compute new target HF
  //     const targetMinted = ethers.parseUnits(targetStats.dscMinted, 18);
  //     const targetCollateralUsd = ethers.parseUnits(targetStats.collateralUsd, 18);

  //     const newTargetDebt = targetMinted > dscAmount ? targetMinted - dscAmount : 0n;
  //     const newTargetCollateralUsd =
  //       targetCollateralUsd > usdValue ? targetCollateralUsd - usdValue : 0n;

  //     let newTargetHF;
  //     if (newTargetDebt === 0n) {
  //       newTargetHF = "∞";
  //     } else {
  //       const hf = await dsceContract.calculateHealthFactor(
  //         newTargetDebt,
  //         newTargetCollateralUsd
  //       );
  //       newTargetHF = Number(ethers.formatUnits(hf, 18)).toFixed(2);
  //     }

  //     // 3️⃣ Update preview
  //     setLiquidationPreview({
  //       base: ethers.formatUnits(baseCollateral, 18),
  //       bonus: ethers.formatUnits(bonusCollateral, 18),
  //       total: ethers.formatUnits(totalCollateral, 18),
  //       usd: ethers.formatUnits(usdValue, 18),
  //       targetHF: newTargetHF,
  //       capped: inputAmount > targetDebt,
  //     });
  //   } catch (err) {
  //     console.error("Failed to preview liquidation:", err);
  //     setLiquidationPreview(null);
  //   }
  // };



  // const handleLiquidateInputChange = async (value) => {
  //   if (!dsceContract || !value || !targetAddress || !targetStats) return;

  //   try {
  //     const inputAmount = Number(value);
  //     const targetDebt = Number(targetStats.dscMinted);

  //     // Clamp UI input, but don't affect calculations (show raw input behavior)
  //     if (inputAmount > targetDebt) {
  //       setLiquidateAmount(value); // don't snap back
  //     } else {
  //       setLiquidateAmount(value);
  //     }

  //     const dscAmount = ethers.parseUnits(value, 18);

  //     // 1️⃣ Base + bonus collateral to receive
  //     const baseCollateral = await dsceContract.getTokenAmountFromDSC(WETH_ADDRESS, dscAmount);
  //     const bonusCollateral = (baseCollateral * 10n) / 100n;
  //     const totalCollateral = baseCollateral + bonusCollateral;
  //     const usdValue = await dsceContract.getUSDValue(WETH_ADDRESS, totalCollateral);

  //     // 2️⃣ Compute new target HF (always compute)
  //     const targetMinted = ethers.parseUnits(targetStats.dscMinted, 18);
  //     const targetCollateralUsd = ethers.parseUnits(targetStats.collateralUsd, 18);

  //     const newTargetDebt = targetMinted > dscAmount ? targetMinted - dscAmount : 0n;
  //     const newTargetCollateralUsd =
  //       targetCollateralUsd > usdValue ? targetCollateralUsd - usdValue : 0n;

  //     const newTargetHF = await dsceContract.calculateHealthFactor(
  //       newTargetDebt,
  //       newTargetCollateralUsd
  //     );

  //     // 3️⃣ Update preview — always show HF, even if it’s absurd
  //     setLiquidationPreview({
  //       base: ethers.formatUnits(baseCollateral, 18),
  //       bonus: ethers.formatUnits(bonusCollateral, 18),
  //       total: ethers.formatUnits(totalCollateral, 18),
  //       usd: ethers.formatUnits(usdValue, 18),
  //       targetHF: Number(ethers.formatUnits(newTargetHF, 18)).toFixed(4),
  //       capped: inputAmount > targetDebt,
  //     });
  //   } catch (err) {
  //     console.error("Failed to preview liquidation:", err);
  //     setLiquidationPreview(null);
  //   }
  // };

  const handleLiquidateInputChange = async (value) => {
    if (!dsceContract || !value || !targetAddress || !targetStats) return;

    try {
      const inputAmount = Number(value);
      const targetDebt = Number(targetStats.dscMinted);

      // Keep user input raw (don’t clamp)
      setLiquidateAmount(value);

      // Parse safely: if user types > debt, just use full debt for math
      const dscAmount = ethers.parseUnits(
        inputAmount > targetDebt ? targetDebt.toString() : value,
        18
      );

      // 1️⃣ Base + bonus collateral to receive
      const baseCollateral = await dsceContract.getTokenAmountFromDSC(WETH_ADDRESS, dscAmount);
      const bonusCollateral = (baseCollateral * 10n) / 100n;
      const totalCollateral = baseCollateral + bonusCollateral;
      const usdValue = await dsceContract.getUSDValue(WETH_ADDRESS, totalCollateral);

      // 2️⃣ Compute new target HF
      const targetMinted = ethers.parseUnits(targetStats.dscMinted, 18);
      const targetCollateralUsd = ethers.parseUnits(targetStats.collateralUsd, 18);

      const newTargetDebt = targetMinted > dscAmount ? targetMinted - dscAmount : 0n;
      const newTargetCollateralUsd =
        targetCollateralUsd > usdValue ? targetCollateralUsd - usdValue : 0n;

      const hf = await dsceContract.calculateHealthFactor(newTargetDebt, newTargetCollateralUsd);
      const newTargetHF = Number(ethers.formatUnits(hf, 18)).toFixed(2);

      // 3️⃣ Update preview
      setLiquidationPreview({
        base: ethers.formatUnits(baseCollateral, 18),
        bonus: ethers.formatUnits(bonusCollateral, 18),
        total: ethers.formatUnits(totalCollateral, 18),
        usd: ethers.formatUnits(usdValue, 18),
        targetHF: newTargetHF,
        overDebt: inputAmount > targetDebt,
      });
    } catch (err) {
      console.error("Failed to preview liquidation:", err);
      setLiquidationPreview(null);
    }
  };





  // Execute liquidation
  const handleLiquidate = async () => {
    try {
      if (!signer) return alert("Connect your wallet first");
      if (!targetAddress || !ethers.isAddress(targetAddress))
        return alert("Enter a valid target address");
      if (!liquidateAmount || Number(liquidateAmount) <= 0)
        return alert("Enter a DSC amount to burn");

      // Build fresh instances (always use new ones per tx to avoid stale refs)
      const engine = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const dscErc20 = new ethers.Contract(
        STABLECOIN_CONTRACT_ADDRESS,
        STABLECOIN_ABI,
        signer
      );

      // Parse the DSC amount
      const amount = ethers.parseUnits(liquidateAmount, 18);

      // (optional) Check wallet DSC balance
      const walletAddr = await signer.getAddress();
      const balance = await dscErc20.balanceOf(walletAddr);
      if (balance < amount) return alert("Not enough DSC to cover liquidation");

      // 1️⃣ Approve engine to spend DSC
      const approveTx = await dscErc20.approve(ENGINE_CONTRACT_ADDRESS, amount);
      await approveTx.wait();

      // 2️⃣ Call engine.liquidate
      const liquidateTx = await engine.liquidate(WETH_ADDRESS, targetAddress, amount);
      await liquidateTx.wait();

      alert("Liquidation successful ✅");

      // Refresh your own stats (liquidator’s stats)
      await fetchUserStats(engine, walletAddr);

      // Optionally: refresh the target stats too
      await fetchTargetUserStats(targetAddress);
    } catch (err) {
      console.error("Liquidation failed:", err);
      alert("Liquidation failed ❌ (check console for details)");
    }
  };


  return (

    <>

      {userAddress ?
        <span className="px-3 py-1 text-s rounded-full bg-green-100 text-green-900">
          {formatAddress(userAddress)}
        </span> : <button
          onClick={connectWallet}
          className="bg-blue-500 text-white px-4 py-2 rounded"
        >
          Connect Wallet
        </button>}


      <div className="min-h-screen bg-gray-50 p-8 space-y-8 flex">

        {/* Deposit & Mint Section */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">Deposit & Mint</h2>
          <div className="flex flex-col gap-3">
            <input
              type="number"
              placeholder="ETH Amount"
              className="border p-2 rounded"
              value={collateralAmount}
              onChange={handleInputCollateralChange}
            />
            <input type="number" placeholder="DSC to Mint" className="border p-2 rounded" value={mintAmount} onChange={(e) => setMintAmount(e.target.value)} />
            <button onClick={handleDepositAndMint} className="bg-blue-500 text-white py-2 px-4 rounded">Deposit & Mint</button>
          </div>
          <div className="mt-4 text-sm text-gray-600 space-y-1">
            <p>ETH/USD Price:  {ethUsdPrice ? `$${ethUsdPrice}` : "Loading..."}</p>
            <p>Max to Mint: {maxMintable ? `${maxMintable} DSC` : "Insert ETH amount"}</p>
          </div>
        </div>

        {/* Burn & Redeem Section */}
        {/* Burn DSC Section */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">Burn DSC</h2>
          <div className="flex flex-col gap-3">
            <input
              type="number"
              placeholder="Amount to Burn"
              className="border p-2 rounded"
              value={burnAmount}
              onChange={(e) => setBurnAmount(e.target.value)}
            />
            <button
              onClick={handleBurnDsc}
              className="bg-red-500 text-white py-2 px-4 rounded"
              disabled={!burnAmount || (userStats && Number(burnAmount) > Number(userStats.dscMinted))}
            >
              Burn DSC
            </button>
            <p className="text-sm text-gray-600">
              Max burnable: {userStats ? `${userStats.dscMinted} DSC` : "..."}
            </p>
          </div>
        </div>

        {/* Redeem Collateral Section */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">Redeem Collateral</h2>
          <div className="flex flex-col gap-3">
            <input
              type="number"
              placeholder="Collateral to Redeem"
              className="border p-2 rounded"
              value={redeemAmount}
              onChange={handleRedeemInputChange}
            />

            <button
              onClick={handleRedeemCollateral}
              className="bg-blue-500 text-white py-2 px-4 rounded"
              disabled={!redeemAmount || (userStats && Number(redeemAmount) > Number(userStats.collateralDeposited))}
            >
              Redeem Collateral
            </button>
            <p className="text-sm text-gray-600">
              Projected HF: {projectedHF ? projectedHF : userStats ? Number(userStats.healthFactor) : ""}
            </p>
            <p className="text-sm text-gray-600">
              Max redeemable: {userStats ? `${userStats.collateralDeposited} WETH` : "..."}
            </p>

          </div>
        </div>


        {/* Liquidation Section */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">Liquidate</h2>
          <div className="flex flex-col gap-3">
            {/* Target Address Input */}
            <input
              type="text"
              placeholder="Target User Address"
              className="border p-2 rounded"
              value={targetAddress}
              onChange={(e) => {
                const addr = e.target.value;
                setTargetAddress(addr);
                if (addr && ethers.isAddress(addr)) {
                  fetchTargetUserStats(addr);
                } else {
                  setTargetStats(null);
                }
              }}
            />

            {/* Target Stats */}
            <div className="mt-3 text-sm space-y-1">
              <p>Target DSC Minted: {targetStats ? targetStats.dscMinted : "..."}</p>
              <p>
                Health Factor:{" "}
                {targetStats ? (
                  <span
                    className={
                      Number(targetStats.healthFactor) < 1
                        ? "text-red-600 font-bold"
                        : Number(targetStats.healthFactor) < 1.2
                          ? "text-yellow-600 font-bold"
                          : Number(targetStats.healthFactor) < 1.5
                            ? "text-orange-500 font-bold"
                            : "text-green-600 font-bold"
                    }
                  >
                    {Number(targetStats.healthFactor).toFixed(2)}{" "}
                    {Number(targetStats.healthFactor) < 1
                      ? "(Liquidatable)"
                      : Number(targetStats.healthFactor) < 1.2
                        ? "(Danger Zone)"
                        : Number(targetStats.healthFactor) < 1.5
                          ? "(At Risk)"
                          : "(Safe)"}
                  </span>
                ) : "..."}
              </p>
            </div>

            {/* Input: DSC to Burn */}
            <input
              type="number"
              placeholder="DSC to Burn"
              className="border p-2 rounded"
              value={liquidateAmount}
              onChange={(e) => {
                setLiquidateAmount(e.target.value);
                handleLiquidateInputChange(e.target.value);
              }}
            />

            {liquidationPreview && (
              <div className="mt-2 text-sm text-gray-600 space-y-1">

                {liquidationPreview.overDebt && (
                  <p className="text-xs text-orange-500 italic">
                    ⚠️ Max burnable = ({targetStats.dscMinted} DSC)
                  </p>
                )}
                <p>
                  You will receive:{" "}
                  {`${Number(liquidationPreview.total).toFixed(6)} WETH (~$${Number(liquidationPreview.usd).toFixed(2)})`}
                </p>
                <p className="italic text-xs text-gray-500">Includes 10% bonus</p>

                <p>
                  Target projected HF after liquidation:{" "}
                  <span
                    className={
                      Number(liquidationPreview.targetHF) < 1
                        ? "text-red-600 font-bold"
                        : Number(liquidationPreview.targetHF) < 1.2
                          ? "text-yellow-600 font-bold"
                          : Number(liquidationPreview.targetHF) < 1.5
                            ? "text-orange-500 font-bold"
                            : "text-green-600 font-bold"
                    }
                  >
                    {liquidationPreview.targetHF}
                  </span>
                </p>


              </div>
            )}



            {/* Liquidate Button */}
            <button
              onClick={handleLiquidate}
              className="bg-purple-600 text-white py-2 px-4 rounded"
              disabled={!targetAddress || !liquidateAmount}
            >
              Liquidate User
            </button>
          </div>
        </div>




        {/* User Stats */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">User Stats</h2>
          <div className="space-y-2">
            <p>
              Health Status:{" "}
              {userStats && (
                <>
                  <span
                    className={
                      Number(userStats.healthFactor) < 1
                        ? "text-red-600 font-bold"
                        : Number(userStats.healthFactor) < 1.2
                          ? "text-yellow-600 font-bold"
                          : Number(userStats.healthFactor) < 1.5
                            ? "text-orange-500 font-bold"
                            : "text-green-600 font-bold"
                    }
                  >
                    {Number(userStats.healthFactor).toFixed(2)}{" "}
                    {Number(userStats.healthFactor) < 1
                      ? "(Liquidatable)"
                      : Number(userStats.healthFactor) < 1.2
                        ? "(Danger Zone)"
                        : Number(userStats.healthFactor) < 1.5
                          ? "(At Risk)"
                          : "(Safe)"}
                  </span>
                </>
              )}
            </p>

            <p>Collateral Deposited: {userStats ? `${userStats.collateralDeposited} WETH` : "..."}</p>
            <p>Collateral Value (USD): {userStats ? `$${userStats.collateralUsd}` : "..."}</p>
            <p>DSC Minted: {userStats ? `${userStats.dscMinted} DSC` : "..."}</p>
          </div>
        </div>

      </div >

    </>
  )
}

