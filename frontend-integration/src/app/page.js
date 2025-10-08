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


  /*//////////////////////////////////////////////////////////////
                         CONNECT WALLET
  //////////////////////////////////////////////////////////////*/
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
      const dsce = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const dsc = new ethers.Contract(STABLECOIN_CONTRACT_ADDRESS, ABI, signer);

      setDsceContract(dsce);
      setDscContract(dsc);

      await fetchUserStats(dsce, address);

    } catch (err) {
      console.error("Wallet connection failed:", err);
    }
  }


  /*//////////////////////////////////////////////////////////////
                         LOAD USER STATS
  //////////////////////////////////////////////////////////////*/
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



  /*//////////////////////////////////////////////////////////////
                         DEPOSIT AND MINT
  //////////////////////////////////////////////////////////////*/
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
        ["function deposit() payable", "function approve(address spender, uint256 amount) public returns (bool)", "function allowance(address owner, address spender) public returns (uint256)"],
        signer
      );
      const tx1 = await weth.deposit({ value: collateral }); // wrap same amount of ETH
      await tx1.wait();

      // Step 2: Approve WETH for DSCEngine
      const tx2 = await weth.approve(ENGINE_CONTRACT_ADDRESS, collateral);
      await tx2.wait();
      // Check existing allowance before approving - dropped for now
      // const currentAllowance = await weth.allowance(userAddress, ENGINE_CONTRACT_ADDRESS);
      // if (currentAllowance < collateral) {
      //   const tx2 = await weth.approve(ENGINE_CONTRACT_ADDRESS, ethers.MaxUint256);
      //   await tx2.wait();
      // }


      // Step 3: Deposit & Mint in DSCEngine
      const tx3 = await dsceContract.depositCollateralAndMintDsc(
        WETH_ADDRESS,
        collateral,
        dscToMint
      );
      await tx3.wait();
      setCollateralAmount("");
      setMintAmount("");
      setEthUsdPrice("");
      setMaxMintable("");
      await fetchUserStats(dsceContract, userAddress);

      alert(" Wrap + Deposit + Mint successful ✅");
    } catch (err) {
      alert("Transaction failed ❌");
    }
  };



  /*//////////////////////////////////////////////////////////////
                        BURN AND REDEEM
  //////////////////////////////////////////////////////////////*/
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

      await fetchUserStats(engine, await signer.getAddress());
      setBurnAmount("");
      alert("LUSD burned successfully ✅");

    } catch (err) {
      console.error("Burn failed:", err);
      alert("Burn failed ❌");
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

      // const weth = new ethers.Contract(WETH_ADDRESS, ["function withdraw(uint256)"], signer);
      const amount = ethers.parseUnits(redeemAmount, 18);

      //Burn DSC and redeem collateral (returns WETH)
      const tx = await dsceContract.redeemCollateral(WETH_ADDRESS, amount);
      await tx.wait();

      // Immediately unwrap WETH → ETH
      // const tx2 = await weth.withdraw(redeemAmount);
      // await tx2.wait();

      await fetchUserStats(dsceContract, userAddress);
      setRedeemAmount("");
      alert("Redeem successful, ETH sent! ✅");
    } catch (err) {
      console.log(err);
      alert("Redeem failed ❌");
    }
  };

  /*//////////////////////////////////////////////////////////////
                        LIQUIDATION
  //////////////////////////////////////////////////////////////*/
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

      // 1 Base + bonus collateral to receive
      const baseCollateral = await dsceContract.getTokenAmountFromDSC(WETH_ADDRESS, dscAmount);
      const bonusCollateral = (baseCollateral * 10n) / 100n;
      const totalCollateral = baseCollateral + bonusCollateral;
      const usdValue = await dsceContract.getUSDValue(WETH_ADDRESS, totalCollateral);

      // 2 Compute new target HF
      const targetMinted = ethers.parseUnits(targetStats.dscMinted, 18);
      const targetCollateralUsd = ethers.parseUnits(targetStats.collateralUsd, 18);

      const newTargetDebt = targetMinted > dscAmount ? targetMinted - dscAmount : 0n;
      const newTargetCollateralUsd =
        targetCollateralUsd > usdValue ? targetCollateralUsd - usdValue : 0n;

      const hf = await dsceContract.calculateHealthFactor(newTargetDebt, newTargetCollateralUsd);
      const newTargetHF = Number(ethers.formatUnits(hf, 18)).toFixed(2);

      // 3 Update preview
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

      // Check wallet DSC balance
      const walletAddr = await signer.getAddress();
      const balance = await dscErc20.balanceOf(walletAddr);
      if (balance < amount) return alert("Not enough DSC to cover liquidation");

      // 1 Approve engine to spend DSC
      const approveTx = await dscErc20.approve(ENGINE_CONTRACT_ADDRESS, amount);
      await approveTx.wait();

      // 2 Call engine.liquidate
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

      <header className=" flex flex-col items-center justify-center w-full border-b border-gray-200 bg-white shadow-sm ">
        {/* Navbar */}
        <nav className="bg-gradient-to-b from-purple-200 flex justify-between items-center w-full  px-6 py-4 md:pt-4 md:pb-0">
          {/* Left: Logo / Stablecoin Name */}
          <div className="flex items-center gap-2">
            <a
              href="https://letiazevedo.com"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 group cursor-pointer"
            >
              <div className="w-8 h-8 rounded-full bg-purple-600 flex items-center justify-center text-white font-bold text-lg">
                L
              </div>
              <h1 className="text-xl font-semibold text-purple-700 hover:text-purple-400">LUSD</h1>
            </a>
          </div>

          {/* Right: Connect Wallet */}
          <div>
            {userAddress ? (
              <button
                className="px-4 py-2 text-sm rounded-full bg-green-100 text-green-900 border border-green-300 hover:bg-green-200 transition-all"
              >
                {formatAddress(userAddress)}
              </button>
            ) : (
              <button
                onClick={connectWallet}
                className="bg-purple-600 text-white px-5 py-2 rounded-full font-medium hover:bg-purple-800 transition-all"
              >
                Connect Wallet
              </button>
            )}
          </div>
        </nav>

        {/* Title Section */}
        <div className="text-center pb-4 mt-10 mb-8">
          <h2 className="text-3xl md:text-4xl font-extrabold text-purple-900">
            Stablecoin Unlock Liquidity with ETH
          </h2>
          <p className="text-gray-600 mt-3 text-base md:text-lg mb-2 px-4">
            Deposit Ethereum to mint LUSD or burn your LUSD to redeem Wrapped Ethereum.
          </p>
        </div>
      </header>

      {/* User Stats Bar */}
      <section className="w-full bg-gradient-to-r from-blue-100 to-purple-100 py-4 border-y border-gray-200 mb-4">
        <div className="max-w-6xl mx-auto flex flex-wrap justify-evenly items-center px-6 gap-4 text-sm md:text-base">
          {/* <div className="max-w-6xl mx-auto grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-y-2 px-6 text-sm md:text-base"> */}

          {/* Health Status */}
          <div className="flex items-center gap-2 relative">
            <span className="text-gray-700 font-semibold">Health Status:</span>
            {userStats ? (
              <span
                className={`font-bold ${Number(userStats.healthFactor) < 1
                  ? "text-red-600"
                  : Number(userStats.healthFactor) < 1.2
                    ? "text-yellow-600"
                    : Number(userStats.healthFactor) < 1.5
                      ? "text-orange-500"
                      : "text-green-600"
                  }`}
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
            ) : (
              <span className="text-gray-400">...</span>
            )}


            {/* Info Icon + Tooltip */}
            <div className="relative group">
              <img
                src="/info.svg"
                alt="info"
                className="w-4 h-4 cursor-pointer opacity-70 hover:opacity-100 transition"
              />

              <div className="absolute left-2 -translate-x-2 hidden group-hover:block bg-gray-600 text-white text-xs rounded-md px-3 py-2 w-64 shadow-lg">
                <p><span className="text-red-400 font-semibold">{"< 1.0"}</span> — Liquidatable: your collateral no longer covers your debt add more collateral or anyone can liquidate you.</p>
                <p><span className="text-yellow-400 font-semibold">1.0–1.2</span> — Danger Zone: very close to liquidation. Add more collateral or burn DSC soon.
                </p>
                <p><span className="text-orange-400 font-semibold">1.2–1.5</span> — At Risk: still safe, but monitor collateral if price drops could push you into danger.</p>
                <p><span className="text-green-400 font-semibold">{"> 1.5"}</span> — Safe: your position is healthy and well-collateralized.</p>
              </div>
            </div>


            {/* Collateral Deposited */}
            <div>
              <span className="text-gray-700 font-semibold">Amount Deposited:</span>{" "}
              <span className="text-gray-800">
                {userStats ? `${userStats.collateralDeposited} WETH` : "..."}
              </span>
            </div>

            {/* Collateral Value */}
            <div >
              <span className="text-gray-700 font-semibold">Collateral Value (USD):</span>{" "}
              <span className="text-gray-800">
                {userStats ? `$${userStats.collateralUsd}` : "..."}
              </span>
            </div>

            {/* LUSD Minted */}
            <div>
              <span className="text-gray-700 font-semibold">LUSD Minted:</span>{" "}
              <span className="text-gray-800">
                {userStats ? `${userStats.dscMinted} DSC` : "..."}
              </span>
            </div>
          </div>
        </div>
      </section>

      <main className=" py-4 px-3">
        <div className="max-w-7xl mx-auto grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
          {/* Deposit & Mint */}
          <div className="p-6 bg-gradient-to-br from-blue-50 via-indigo-100 to-blue-200 rounded-2xl shadow-md border border-blue-200 hover:shadow-lg transition-shadow">
            <h2 className="text-lg font-semibold text-blue-800 mb-2 flex items-center gap-2">
              💵 Deposit & Mint
            </h2>
            <div className="flex flex-col gap-3">
              <input
                type="number"
                placeholder="ETH Amount"
                className="border border-blue-200 p-2 rounded-md focus:ring-2 focus:ring-blue-400 outline-none"
                value={collateralAmount}
                onChange={handleInputCollateralChange}
              />
              <input
                type="number"
                placeholder="LUSD to Mint"
                className="border border-blue-200 p-2 rounded-md focus:ring-2 focus:ring-blue-400 outline-none"
                value={mintAmount}
                onChange={(e) => setMintAmount(e.target.value)}
              />
              <button
                onClick={handleDepositAndMint}
                className="bg-blue-600 hover:bg-blue-700 text-white py-2 rounded-lg font-medium transition-all"
              >
                {"Wrap > Deposit > Mint"}
              </button>
            </div>
            <div className="mt-4 text-sm text-gray-700 space-y-1">
              <p>ETH/USD Price: {ethUsdPrice ? `$${ethUsdPrice}` : "..."}</p>
              <p>Max to Mint: {maxMintable ? `${maxMintable} DSC` : "..."}</p>
            </div>
          </div>

          {/* Burn DSC */}
          <div className="p-6 bg-gradient-to-br from-rose-50 via-rose-100 to-red-200 rounded-2xl shadow-md border border-rose-200 hover:shadow-lg transition-shadow">
            <h2 className="text-lg font-semibold text-red-700 mb-2 flex items-center gap-2">
              🔥 Burn LUSD
            </h2>
            <div className="flex flex-col gap-3">
              <input
                type="number"
                placeholder="Amount to Burn"
                className="border border-rose-200 p-2 rounded-md focus:ring-2 focus:ring-red-400 outline-none"
                value={burnAmount}
                onChange={(e) => setBurnAmount(e.target.value)}
              />
              <button
                onClick={handleBurnDsc}
                className="bg-red-500 hover:bg-red-600 text-white py-2 rounded-lg font-medium transition-all"
                disabled={!burnAmount || (userStats && Number(burnAmount) > Number(userStats.dscMinted))}
              >
                Burn LUSD
              </button>
              <p className="text-sm text-gray-700">
                Max burnable: {userStats ? `${userStats.dscMinted} LUSD` : "..."}
              </p>
            </div>
          </div>

          {/* Redeem Collateral */}
          <div className="p-6 bg-gradient-to-br from-green-50 via-green-100 to-emerald-200 rounded-2xl shadow-md border border-green-200 hover:shadow-lg transition-shadow">
            <h2 className="text-lg font-semibold text-green-700 mb-2 flex items-center gap-2">
              Redeem WETH
            </h2>
            <div className="flex flex-col gap-3">
              <input
                type="number"
                placeholder="Collateral to Redeem"
                className="border border-green-200 p-2 rounded-md focus:ring-2 focus:ring-green-400 outline-none"
                value={redeemAmount}
                onChange={handleRedeemInputChange}
              />
              <button
                onClick={handleRedeemCollateral}
                className="bg-green-600 hover:bg-green-700 text-white py-2 rounded-lg font-medium transition-all"
                disabled={!redeemAmount || (userStats && Number(redeemAmount) > Number(userStats.collateralDeposited))}
              >
                Redeem Collateral
              </button>
              <div className="text-sm text-gray-700 space-y-1">
                <p>Projected Health Status: {projectedHF || (userStats ? Number(userStats.healthFactor).toFixed(2) : "")}</p>
                <p>Max redeemable: {userStats ? `${userStats.collateralDeposited} WETH` : "..."}</p>
              </div>
            </div>
          </div>

          {/* Liquidate */}
          <div className="p-6 bg-gradient-to-br from-white to-indigo-100 rounded-2xl shadow-md border border-indigo-200 hover:shadow-lg transition-shadow">
            <h2 className="text-lg font-semibold text-indigo-700 mb-2 flex items-center gap-2">
              Liquidate
            </h2>

            <div className="flex flex-col gap-3">
              {/* Target Address */}
              <input
                type="text"
                placeholder="Check User Address"
                className="border border-indigo-200 p-2 rounded-md focus:ring-2 focus:ring-indigo-400 outline-none"
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
              <div className="text-sm space-y-1 text-gray-700">
                <p>Target LUSD Minted: <span className="font-medium">{targetStats ? targetStats.dscMinted : "..."}</span></p>
                <p>
                  Health Status:{" "}
                  {targetStats ? (
                    <span
                      className={`font-bold ${Number(targetStats.healthFactor) < 1
                        ? "text-red-600"
                        : Number(targetStats.healthFactor) < 1.2
                          ? "text-yellow-600"
                          : Number(targetStats.healthFactor) < 1.5
                            ? "text-orange-500"
                            : "text-green-600"
                        }`}
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
                  ) : (
                    "..."
                  )}
                </p>
              </div>

              {/* DSC to Burn */}
              <input
                type="number"
                placeholder="LUSD to Burn"
                className="border border-indigo-200 p-2 rounded-md focus:ring-2 focus:ring-indigo-400 outline-none"
                value={liquidateAmount}
                onChange={(e) => {
                  setLiquidateAmount(e.target.value);
                  handleLiquidateInputChange(e.target.value);
                }}
              />

              {/* Preview — amount received + projected target HF */}
              <div className="text-sm text-gray-700 space-y-1">
                {/* Over-burn warning (uses your existing .overDebt flag) */}
                {liquidationPreview?.overDebt && (
                  <p className="text-xs text-orange-600 italic">
                    ⚠️ Max burnable: {targetStats?.dscMinted ?? "..."} LUSD
                  </p>
                )}

                <p>
                  You’ll receive:{" "}
                  {/* <span className="font-semibold text-indigo-800">
                      {Number(liquidationPreview.total).toFixed(6)} WETH (~$
                      {Number(liquidationPreview.usd).toFixed(2)})
                    </span> */}
                  <span className="font-semibold text-indigo-800">
                    {liquidationPreview
                      ? `${Number(liquidationPreview.total).toFixed(6)} WETH (~$${Number(
                        liquidationPreview.usd
                      ).toFixed(2)})`
                      : "..."}
                  </span>
                  <span className="italic text-xs text-gray-500"> Includes 10% bonus</span>
                </p>
                {/* <p className="italic text-xs text-gray-500">Includes 10% bonus</p> */}

                <p>
                  Target Health after burn:{" "}
                  {/* <span
                      className={`font-bold ${Number(liquidationPreview?.targetHF) < 1
                        ? "text-red-600"
                        : Number(liquidationPreview?.targetHF) < 1.2
                          ? "text-yellow-600"
                          : Number(liquidationPreview?.targetHF) < 1.5
                            ? "text-orange-500"
                            : "text-green-600"
                        }`}
                    >
                      {liquidationPreview.targetHF}
                    </span> */}
                  <span
                    className={`font-bold ${liquidationPreview
                      ? Number(liquidationPreview.targetHF) < 1
                        ? "text-red-600"
                        : Number(liquidationPreview.targetHF) < 1.2
                          ? "text-yellow-600"
                          : Number(liquidationPreview.targetHF) < 1.5
                            ? "text-orange-500"
                            : "text-green-600"
                      : "text-gray-400"
                      }`}
                  >
                    {liquidationPreview ? liquidationPreview.targetHF : "..."}
                  </span>
                </p>
              </div>


              {/* Action */}
              <button
                onClick={handleLiquidate}
                className=" bg-indigo-600 hover:bg-indigo-700 text-white py-2 rounded-lg font-medium transition-all disabled:opacity-60"
                disabled={!targetAddress || !liquidateAmount}
              >
                Liquidate User
              </button>
            </div>
          </div>


        </div>
      </main>


    </>
  )
}

