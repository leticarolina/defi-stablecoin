'use client';

import { ethers } from "ethers";
import { useState } from "react"
import { UserStats } from "./components/UserStats";
import { TitleAndSubTitle } from "./components/TitleAndDescription";
import { Navbar } from "./components/NavBar";
import { Card } from "./components/Card";

/* -------------------------- helpers -------------------------- */

export default function Home() {
  const WETH_ADDRESS = "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9";
  const STABLECOIN_CONTRACT_ADDRESS = "0x8cA1a0E543b8C02B29e5e9C3f7EC18EEb82b157f";
  const ENGINE_CONTRACT_ADDRESS = "0xF525ff53e1a384eBFe58b5F4E11FD82721DD25A4";
  // const ENGINE_CONTRACT_ADDRESSOLD = "0xdb1b8fc2a20f7b85cf7571a6fefd74124ddde037";
  // const STABLECOIN_CONTRACT_ADDRESSOLD = "0xbddf447bc2cadac318b97d47b37589235b48d8bc";

  const ABI = [
    // ===== Core Actions =====
    "function depositCollateralAndMintAZD(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountAZDToMint)",
    "function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)",
    "function burnAZD(uint256 amount)",
    "function mintAZD(uint256 amount)",
    "function liquidate(address collateral, address user, uint256 debtToCover)",

    // ===== Getters / Views =====
    "function calculateHealthFactor(uint256 totalAZDMinted, uint256 collateralValueInUsd) view returns (uint256)",
    "function getAccountCollateralValue(address user) view returns (uint256)",
    "function getAccountInformation(address user) view returns (uint256 totalAZDMinted, uint256 collateralValueInUsd)",
    "function getCollateralDeposited(address user, address token) view returns (uint256)",
    "function getCollateralTokens() view returns (address[])",
    "function getAZDMinted(address user) view returns (uint256)",
    "function getHealthFactor(address user) view returns (uint256)",
    "function getTokenAmountFromAZD(address token, uint256 AZDAmount) view returns (uint256)",
    "function getUSDValue(address token, uint256 amount) view returns (uint256)",

    // ===== Events =====
    "event CollateralDeposited(address indexed user, address indexed token, uint256 amount)",
    "event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount)",
    "event AZDMinted(address indexed user, uint256 amountAZDMinted)",
    "event AZDBurned(uint256 amountAZDToBurn, address indexed AZDFrom, address indexed onBehalfOf)"
  ]

  const STABLECOIN_ABI = [
    "function balanceOf(address owner) view returns (uint256)",
    "function transfer(address to, uint256 amount) returns (bool)",
    "function approve(address spender, uint256 amount) returns (bool)"
  ];


  const [AZDeContract, setAZDeContract] = useState(null);
  const [AZDContract, setAZDContract] = useState(null);
  const [userAddress, setUserAddress] = useState(null);
  const [userStats, setUserStats] = useState(null);
  const [collateralAmount, setCollateralAmount] = useState("");
  const [mintAmount, setMintAmount] = useState("");
  const [maxMintable, setMaxMintable] = useState("");
  const [ethUsdPrice, setEthUsdPrice] = useState(null);
  const [signer, setSigner] = useState(null);
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
      alert("Wallet not found! Please install or use desktop.");
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
      const AZDe = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const AZD = new ethers.Contract(STABLECOIN_CONTRACT_ADDRESS, STABLECOIN_ABI, signer);

      setAZDeContract(AZDe);
      setAZDContract(AZD);

      await fetchUserStats(AZDe, address);

    } catch (err) {
      console.error("Wallet connection failed:", err);
    }
  }


  /*//////////////////////////////////////////////////////////////
                         LOAD USER STATS
  //////////////////////////////////////////////////////////////*/
  const fetchUserStats = async (contract = AZDeContract, user = userAddress) => {
    if (!contract || !user) return;

    try {
      const [totalAZDMinted, collateralValueInUsd] =
        await contract.getAccountInformation(user);

      const collateralDeposited = await contract.getCollateralDeposited(user, WETH_ADDRESS);
      const healthFactor = await contract.getHealthFactor(user);

      setUserStats({
        AZDMinted: Number(ethers.formatUnits(totalAZDMinted, 18)).toFixed(2),
        collateralUSD: Number(ethers.formatUnits(collateralValueInUsd, 18)).toFixed(2),
        collateralDeposited: Number(ethers.formatUnits(collateralDeposited, 18)).toFixed(6),
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

    if (!AZDeContract || !value) return;

    try {
      // call contract for USD value
      const usdValue = await AZDeContract.getUSDValue(WETH_ADDRESS, ethers.parseUnits(value, 18)); //smart contract expect the value in wei 1234567890000000000
      setEthUsdPrice(Number(ethers.formatUnits(usdValue, 18)).toFixed(2)); //convert back from raw integer get a string like "1.234567890123456789"

      const max = (usdValue * 80n) / 100n; // apply protocol rule to 80% liquidation threshold
      setMaxMintable(Number(ethers.formatUnits(max, 18)).toFixed(2));


    } catch (err) {
      console.error("Failed to calculate mintable:", err);
    }
  };

  //Each transaction (swap deposit() → approve() → depositCollateralAndMintAZD()) is a separate on-chain call, so MetaMask asks you to confirm all three.
  const handleDepositAndMint = async () => {
    try {
      if (!AZDeContract || !signer) return;

      const collateral = ethers.parseUnits(collateralAmount, 18); //user inputs
      const AZDToMint = ethers.parseUnits(mintAmount, 18);

      // Step 1: Wrap ETH into WETH
      const weth = new ethers.Contract(
        WETH_ADDRESS,
        ["function deposit() payable", "function approve(address spender, uint256 amount) public returns (bool)", "function allowance(address owner, address spender) public returns (uint256)"],
        signer
      );
      const tx1 = await weth.deposit({ value: collateral }); // wrap same amount of ETH
      await tx1.wait();

      // Step 2: Approve WETH for AZDEngine
      const tx2 = await weth.approve(ENGINE_CONTRACT_ADDRESS, collateral);
      await tx2.wait();


      // Step 3: Deposit & Mint in AZDEngine
      const tx3 = await AZDeContract.depositCollateralAndMintAZD(
        WETH_ADDRESS,
        collateral,
        AZDToMint
      );
      await tx3.wait();
      await fetchUserStats(AZDeContract, userAddress);

      setCollateralAmount("");
      setMintAmount("");
      setEthUsdPrice("");
      setMaxMintable("");

      alert(" Wrap + Deposit + Mint successful ✅");
    } catch (err) {
      alert("Transaction failed ❌");
    }
  };



  /*//////////////////////////////////////////////////////////////
                        BURN AND REDEEM
  //////////////////////////////////////////////////////////////*/
  const handleBurnAZD = async () => {
    try {
      if (!signer) return alert("Connect your wallet first");

      // Build fresh instances from the current signer (defensive)
      const engine = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const AZDErc20 = new ethers.Contract(
        STABLECOIN_CONTRACT_ADDRESS,
        STABLECOIN_ABI,
        signer
      );

      // Parse amount and optional client-side check
      const amount = ethers.parseUnits(burnAmount || "0", 18);
      if (amount === 0n) return alert("Enter an amount to burn");

      // make sure user has enough AZD
      const bal = await AZDErc20.balanceOf(await signer.getAddress());
      if (bal < amount) return alert("Not enough AZD to burn");

      // 1) approve engine to pull the AZD
      const tx1 = await AZDErc20.approve(ENGINE_CONTRACT_ADDRESS, amount);
      await tx1.wait();

      // 2) call engine.burnAZD
      const tx2 = await engine.burnAZD(amount);
      await tx2.wait();

      await fetchUserStats(engine, await signer.getAddress());
      setBurnAmount("");
      alert("AZD burned successfully ✅");

    } catch (err) {
      alert("Burn failed ❌");
    }
  };


  const handleRedeemInputChange = async (e) => {
    const value = e.target.value;
    setRedeemAmount(value);

    if (!AZDeContract || !userStats || !value) return;

    try {
      // Convert WETH amount to USD
      const usdValue = await AZDeContract.getUSDValue(
        WETH_ADDRESS,
        ethers.parseUnits(value, 18)
      );

      // new collateral value after redeem
      const newCollateralValue = BigInt(
        ethers.parseUnits(userStats.collateralUSD, 18)
      ) - usdValue;

      // calculate new health factor
      const newHF = await AZDeContract.calculateHealthFactor(
        ethers.parseUnits(userStats.AZDMinted, 18),
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
      if (!AZDeContract || !signer) return;

      const amount = ethers.parseUnits(redeemAmount, 18);

      //Burn AZD and redeem collateral (returns WETH)
      const tx = await AZDeContract.redeemCollateral(WETH_ADDRESS, amount);
      await tx.wait();
      await fetchUserStats(AZDeContract, userAddress);
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
  const fetchTargetUserStats = async (addr) => {
    if (!AZDeContract || !addr) return;
    try {
      const [totalAZDMinted, collateralValueInUsd] =
        await AZDeContract.getAccountInformation(addr);

      const healthFactor = await AZDeContract.getHealthFactor(addr);

      setTargetStats({
        AZDMinted: ethers.formatUnits(totalAZDMinted, 18),
        collateralUSD: ethers.formatUnits(collateralValueInUsd, 18),
        healthFactor: ethers.formatUnits(healthFactor, 18),
      });
    } catch (err) {
      alert("Failed to fetch target stats:", err);
      setTargetStats(null);
    }
  };

  const handleLiquidateInputChange = async (value) => {
    if (!AZDeContract || !value || !targetAddress || !targetStats) return;

    try {
      const inputAmount = Number(value);
      const targetDebt = Number(targetStats.AZDMinted);

      // Keep user input raw
      setLiquidateAmount(value);

      // Parse safely: if user types > debt, just use full debt for math
      const AZDAmount = ethers.parseUnits(
        inputAmount > targetDebt ? targetDebt.toString() : value,
        18
      );

      // 1 Base + bonus collateral to receive
      const baseCollateral = await AZDeContract.getTokenAmountFromAZD(WETH_ADDRESS, AZDAmount);
      const bonusCollateral = (baseCollateral * 10n) / 100n;
      const totalCollateral = baseCollateral + bonusCollateral;
      const usdValue = await AZDeContract.getUSDValue(WETH_ADDRESS, totalCollateral);

      // 2 Compute new target HF
      const targetMinted = ethers.parseUnits(targetStats.AZDMinted, 18);
      const targetcollateralUSD = ethers.parseUnits(targetStats.collateralUSD, 18);

      const newTargetDebt = targetMinted > AZDAmount ? targetMinted - AZDAmount : 0n;
      const newTargetcollateralUSD =
        targetcollateralUSD > usdValue ? targetcollateralUSD - usdValue : 0n;

      const hf = await AZDeContract.calculateHealthFactor(newTargetDebt, newTargetcollateralUSD);
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
        return alert("Enter a AZD amount to burn");

      // Build fresh instances (to avoid stale refs)
      const engine = new ethers.Contract(ENGINE_CONTRACT_ADDRESS, ABI, signer);
      const AZDErc20 = new ethers.Contract(
        STABLECOIN_CONTRACT_ADDRESS,
        STABLECOIN_ABI,
        signer
      );

      // Parse the AZD amount
      const amount = ethers.parseUnits(liquidateAmount, 18);

      // Check wallet AZD balance
      const walletAddr = await signer.getAddress();
      const balance = await AZDErc20.balanceOf(walletAddr);
      if (balance < amount) return alert("Not enough AZD to cover liquidation");

      // 1 Approve engine to spend AZD
      const approveTx = await AZDErc20.approve(ENGINE_CONTRACT_ADDRESS, amount);
      await approveTx.wait();

      // 2 Call engine.liquidate
      const liquidateTx = await engine.liquidate(WETH_ADDRESS, targetAddress, amount);
      await liquidateTx.wait();

      alert("Liquidation successful ✅");

      // Refresh target and your own stats 
      await fetchUserStats(engine, walletAddr);
      await fetchTargetUserStats(targetAddress);
    } catch (err) {
      console.error("Liquidation failed:", err);
      alert("Liquidation failed ❌");
    }
  };


  return (

    <>

      <header className=" flex flex-col items-center justify-center w-full border-b border-gray-200 bg-white shadow-sm ">
        {/* Navbar */}
        <Navbar userAddress={userAddress} connectWallet={connectWallet}></Navbar>

        {/* Title Section */}
        <TitleAndSubTitle title={"Unlock Liquidity with Your ETH"}
          subtitle={"Deposit Ethereum to mint AZD ($1 stablecoin), or burn AZD to redeem WETH."} />

      </header >

      {/* User Stats Bar */}
      < section className="w-full bg-gradient-to-r from-blue-100 to-purple-100 py-4 border-y border-gray-200 mb-4" >
        <div className="max-w-6xl mx-auto flex flex-wrap justify-evenly items-center px-6 text-sm md:text-base">
          {/* <div className="max-w-6xl mx-auto grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-y-2 px-6 text-sm md:text-base"> */}

          {/* Health Status */}
          <div className="flex items-center relative gap-8 flex-wrap">
            {/* Info Icon + Tooltip */}
            <div className="flex gap-1 items-center">
              <div className="relative group">
                <img
                  src="/info.svg"
                  alt="info"
                  className="w-4 h-4 cursor-pointer opacity-70 hover:opacity-100 transition"
                />

                <div className="absolute left-2 -translate-x-2 hidden group-hover:block bg-gray-600 text-white text-xs rounded-md px-3 py-2 w-64 shadow-lg">
                  <p><span className="text-red-400 font-semibold">{"< 1.0"}</span> — Liquidatable: your collateral no longer covers your debt add more collateral or anyone can liquidate you.</p>
                  <p><span className="text-yellow-400 font-semibold">1.0–1.2</span> — Danger Zone: very close to liquidation. Add more collateral or burn AZD soon.
                  </p>
                  <p><span className="text-orange-400 font-semibold">1.2–1.5</span> — At Risk: still safe, but monitor collateral if price drops could push you into danger.</p>
                  <p><span className="text-green-400 font-semibold">{"> 1.5"}</span> — Safe: your position is healthy and well-collateralized.</p>
                </div>
              </div>



              <span className="text-gray-700 font-semibold">Health Status:</span>
              {userStats ? (
                (() => {
                  const hf = Number(userStats.healthFactor);
                  const displayHF =
                    !isFinite(hf) || hf > 1000 ? "Safe" : hf.toFixed(2);

                  const color =
                    !isFinite(hf) || hf > 1000
                      ? "text-green-600"
                      : hf < 1
                        ? "text-red-600"
                        : hf < 1.2
                          ? "text-yellow-600"
                          : hf < 1.5
                            ? "text-orange-500"
                            : "text-green-600";

                  const label =
                    !isFinite(hf) || hf > 1000
                      ? "(Safe)"
                      : hf < 1
                        ? "(Liquidatable)"
                        : hf < 1.2
                          ? "(Danger Zone)"
                          : hf < 1.5
                            ? "(At Risk)"
                            : "(Safe)";

                  return (
                    <span className={`font-bold ${color}`}>
                      {displayHF} {label}
                    </span>
                  );
                })()
              ) : (
                <span className="text-gray-400">...</span>
              )}
            </div>


            {/* Collateral Deposited, Collateral Value and AZD Minted */}
            <UserStats statTitle={"Amount Deposited:"}> {userStats ? `${userStats.collateralDeposited} WETH` : "..."}</UserStats>
            <UserStats statTitle={"Collateral Value (USD):"}> {userStats ? `$${userStats.collateralUSD}` : "..."}</UserStats>
            <UserStats statTitle={"AZD Minted:"}>  {userStats ? `${userStats.AZDMinted} AZD` : "..."}</UserStats>

          </div>
        </div>
      </section >

      <main className=" py-4 px-3">
        <div className="max-w-7xl mx-auto grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">

          {/* Deposit & Mint */}
          <Card title="💵 Deposit & Mint" color="blue">
            {/* Specific inputs + button + logic */}
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
                placeholder="AZD to Mint"
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
              <p>Max to Mint: {maxMintable ? `${maxMintable} AZD` : "..."}</p>
            </div>
          </Card>

          {/* Burn AZD */}
          <Card title="🔥 Burn AZD" color="red">
            <div className="flex flex-col gap-3">
              <input
                type="number"
                placeholder="Amount to Burn"
                className="border border-rose-200 p-2 rounded-md focus:ring-2 focus:ring-red-400 outline-none"
                value={burnAmount}
                onChange={(e) => setBurnAmount(e.target.value)}
              />
              <button
                onClick={handleBurnAZD}
                className="bg-red-500 hover:bg-red-600 text-white py-2 rounded-lg font-medium transition-all"
                disabled={!burnAmount || (userStats && Number(burnAmount) > Number(userStats.AZDMinted))}
              >
                Burn AZD
              </button>
              <p className="text-sm text-gray-700">
                Max burnable: {userStats ? `${userStats.AZDMinted} AZD` : "..."}
              </p>
            </div>
          </Card>

          {/* Redeem Collateral */}
          <Card title="Redeem WETH" color="green">
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
                {/* <p>Projected Health Status: {projectedHF || (userStats ? Number(userStats.healthFactor).toFixed(2) : "")}</p> */}
                <p>
                  Projected Health Status:{" "}
                  {(() => {
                    const hf = Number(projectedHF || (userStats ? userStats.healthFactor : 0));
                    if (!isFinite(hf) || hf > 1000) return "Safe";
                    return hf.toFixed(2);
                  })()}
                </p>
                <p>Max redeemable: {userStats ? `${userStats.collateralDeposited} WETH` : "..."}</p>
              </div>
            </div>
          </Card>


          {/* Liquidate */}
          <Card title="Liquidate" color="indigo">

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
                <p>Target AZD Minted: <span className="font-medium">{targetStats ? Number(targetStats.AZDMinted).toFixed(2) : "..."}</span></p>
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

              {/* AZD to Burn */}
              <input
                type="number"
                placeholder="AZD to Burn"
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
                    ⚠️ Max burnable: {targetStats?.AZDMinted ?? "..."} AZD
                  </p>
                )}

                <p>
                  You’ll receive:{" "}
                  <span className="font-semibold text-indigo-800">
                    {liquidationPreview
                      ? `${Number(liquidationPreview.total).toFixed(6)} WETH (~$${Number(
                        liquidationPreview.usd
                      ).toFixed(2)})`
                      : "..."}
                  </span>
                  <span className="italic text-xs text-gray-500"> Includes 10% bonus</span>
                </p>

                <p>
                  Target Health after burn:{" "}
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


          </Card>


        </div>
      </main>


    </>
  )
}

