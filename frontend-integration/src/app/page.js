'use client';

import Image from "next/image";
import { ethers } from "ethers";
import { useEffect, useState } from "react"


// const ABI = [
//   // ===== Core Actions =====
//   "function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)",
//   "function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToMint)",
//   "function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)",
//   "function burnDsc(uint256 amount)",
//   "function burnDscAndRedeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)",
//   "function mintDsc(uint256 amount)",
//   "function liquidate(address collateral, address user, uint256 debtToCover)",

//   // ===== Getters / Views =====
//   "function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) view returns (uint256)",
//   "function getAccountCollateralValue(address user) view returns (uint256)",
//   "function getAccountInformation(address user) view returns (uint256 totalDscMinted, uint256 collateralValueInUsd)",
//   "function getCollateralDeposited(address user, address token) view returns (uint256)",
//   "function getCollateralTokens() view returns (address[])",
//   "function getDSCMinted(address user) view returns (uint256)",
//   "function getHealthFactor(address user) view returns (uint256)",
//   "function getLiquidationThreshold() view returns (uint256)",
//   "function getMinHealthFactor() view returns (uint256)",
//   "function getPrecision() view returns (uint256)",
//   "function getPriceFeed(address token) view returns (address)",
//   "function getTokenAmountFromDSC(address token, uint256 dscAmount) view returns (uint256)",
//   "function getUSDValue(address token, uint256 amount) view returns (uint256)",

//   // ===== Events =====
//   'event CollateralDeposited(address indexed user,address indexed token,uint256 indexed amount)',
//   'event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemedTo, address indexed token,uint256 amount)',
//   'event DSCMinted(address indexed user, uint256 indexed amountDSCMinted)',
//   'event DSCBurned(uint256 indexed amountDSCToBurn,address indexed dscFrom,address indexed onBehalfOf)',
// ];

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

  // const STABLECOIN_ABI = [
  //   "function name() view returns (string)",
  //   "function symbol() view returns (string)",
  //   "function decimals() view returns (uint8)",
  //   "function balanceOf(address owner) view returns (uint256)",
  //   "function transfer(address to, uint256 amount) returns (bool)",
  //   "function approve(address spender, uint256 amount) returns (bool)"
  // ];


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
      const [totalDscMinted, collateralValueInUsd] =
        await contract.getAccountInformation(user);

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




  const handleCollateralChange = async (e) => {
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
      await fetchUserStats(dsceContract, userAddress);

      // Step 3: Deposit & Mint in DSCEngine
      const tx3 = await dsceContract.depositCollateralAndMintDsc(
        WETH_ADDRESS,
        collateral,
        dscToMint
      );
      await tx3.wait();

      alert("Deposit + Wrap + Mint successful ✅");
    } catch (err) {
      console.error("Deposit & Mint failed:", err);
      alert("Transaction failed ❌");
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
              onChange={handleCollateralChange}
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
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">Burn & Redeem</h2>
          <div className="flex flex-col gap-3">
            <input type="text" placeholder="Collateral to Redeem" className="border p-2 rounded" />
            <input type="text" placeholder="DSC to Burn" className="border p-2 rounded" />
            <button className="bg-red-500 text-white py-2 px-4 rounded">Burn & Redeem</button>
          </div>
        </div>

        {/* Liquidation Section */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">Liquidate</h2>
          <div className="flex flex-col gap-3">
            <input type="text" placeholder="User Address to Liquidate" className="border p-2 rounded" />
            <input type="text" placeholder="Collateral Token Address" className="border p-2 rounded" />
            <input type="text" placeholder="Debt to Cover" className="border p-2 rounded" />
            <button className="bg-purple-600 text-white py-2 px-4 rounded">Liquidate</button>
          </div>
        </div>


        {/* User Stats */}
        <div className="p-6 bg-white rounded-xl shadow">
          <h2 className="text-xl font-bold mb-4">User Stats</h2>
          <div className="space-y-2">
            {/* <div>
              <p className="text-sm text-gray-600 mb-1">Health Factor</p>
              <div className="w-full bg-gray-200 rounded h-4">
                <div
                  className={`h-4 rounded ${userStats && Number(userStats.healthFactor) < 1.2
                    ? "bg-red-500"
                    : "bg-green-500"
                    }`}
                  style={{
                    width: `${Math.min(Number(userStats?.healthFactor) * 20, 100)}%`,
                  }}
                ></div>
              </div>
              <p className="text-xs">
                {userStats ? Number(userStats.healthFactor).toFixed(2) : "..."}
              </p>
            </div> */}
            <p>Collateral Deposited: {userStats ? `${userStats.collateralDeposited} WETH` : "..."}</p>
            <p>Collateral Value (USD): {userStats ? `$${userStats.collateralUsd}` : "..."}</p>
            <p>DSC Minted: {userStats ? `${userStats.dscMinted} DSC` : "..."}</p>
          </div>
        </div>

      </div>

    </>
  )
}

