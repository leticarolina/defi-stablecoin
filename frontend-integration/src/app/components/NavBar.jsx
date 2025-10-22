import Image from "next/image";

export function Navbar({ userAddress, connectWallet }) {
  return (
    <nav className="bg-gradient-to-b from-purple-200 flex justify-between items-center w-full px-10 py-4">
      <a href="https://letiazevedo.com" target="_blank" rel="noopener noreferrer"
        className="flex items-center gap-2 group cursor-pointer">
        <Image src="/logo.png" alt="AZD Logo" width={40} height={40}
          className="rounded-full object-contain hover:scale-105 transition-transform duration-200"
        />
        <h1 className="text-xl font-semibold text-purple-900 hover:text-purple-400">AZD</h1>
      </a>

      {userAddress ? (
        <button className="px-4 py-2 text-sm rounded-full bg-green-100 text-green-900 border border-green-300 hover:bg-green-200 transition-all">
          {userAddress.slice(0, 6)}...{userAddress.slice(-4)}
        </button>
      ) : (
        <button
          onClick={connectWallet}
          className="bg-purple-800 text-white px-5 py-2 rounded-full font-medium hover:bg-purple-600 transition-all">
          Connect Wallet
        </button>
      )}
    </nav>
  );
}





// <nav className="bg-gradient-to-b from-purple-200 flex justify-between items-center w-full px-10 py-4">
//           {/* Left: Logo / Stablecoin Name */}
//           <div className="flex items-center gap-2">
//             <a
//               href="https://letiazevedo.com"
//               target="_blank"
//               rel="noopener noreferrer"
//               className="flex items-center gap-2 group cursor-pointer"
//             >
//               <Image
//                 src="/logo.png"
//                 alt="AZD Logo"
//                 width={40}
//                 height={40}
//                 className="rounded-full object-contain hover:scale-105 transition-transform duration-200"
//               />
//               <h1 className="text-xl font-semibold text-purple-900 hover:text-purple-400">AZD</h1>
//             </a>
//           </div>

//           {/* Right: Connect Wallet */}
//           <div>
//             {userAddress ? (
//               <button
//                 className="px-4 py-2 text-sm rounded-full bg-green-100 text-green-900 border border-green-300 hover:bg-green-200 transition-all"
//               >
//                 {formatAddress(userAddress)}
//               </button>
//             ) : (
//               <button
//                 onClick={connectWallet}
//                 className="bg-purple-800 text-white px-5 py-2 rounded-full font-medium hover:bg-purple-600 transition-all"
//               >
//                 Connect Wallet
//               </button>
//             )}
//           </div>
//         </nav>