import Image from "next/image";

export default function Home() {

  return (
    <div className="min-h-screen bg-gray-50 p-8 space-y-8 flex">

      {/* Deposit & Mint Section */}
      <div className="p-6 bg-white rounded-xl shadow">
        <h2 className="text-xl font-bold mb-4">Deposit & Mint</h2>
        <div className="flex flex-col gap-3">
          <input type="text" placeholder="Collateral Amount" className="border p-2 rounded" />
          <input type="text" placeholder="DSC to Mint" className="border p-2 rounded" />
          <button className="bg-blue-500 text-white py-2 px-4 rounded">Deposit & Mint</button>
        </div>
        <div className="mt-4 text-sm text-gray-600 space-y-1">
          <p>Max Mintable: ...</p>
          <p>Adjusted Collateral: ...</p>
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
          {/* Health Factor Bar */}
          <div>
            <p className="text-sm text-gray-600 mb-1">Health Factor</p>
            <div className="w-full bg-gray-200 rounded h-4">
              <div
                className="bg-green-500 h-4 rounded"
                style={{ width: "80%" }} // dynamically controlled later
              ></div>
            </div>
          </div>
          <p>Collateral Deposited: ...</p>
          <p>DSC Minted: ...</p>
          <p>Collateral Value (USD): ...</p>
        </div>
      </div>
    </div>
  );




}
