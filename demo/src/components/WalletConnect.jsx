import { shortenAddress } from '../utils/contracts'
import './WalletConnect.css'

function WalletConnect({ web3 }) {
  if (!web3.isConnected) {
    return (
      <button 
        className="connect-btn"
        onClick={web3.connectWallet}
        disabled={web3.isConnecting}
      >
        {web3.isConnecting ? 'CONNECTING...' : 'CONNECT WALLET'}
      </button>
    )
  }

  return (
    <div className="wallet-info">
      <div className="wallet-address">{shortenAddress(web3.account)}</div>
      <button className="disconnect-btn" onClick={web3.disconnect}>
        DISCONNECT
      </button>
    </div>
  )
}

export default WalletConnect

