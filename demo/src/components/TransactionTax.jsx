import { useState, useEffect } from 'react'
import { parseTokenAmount, formatTokenAmount, shortenAddress } from '../utils/contracts'
import { parseError, checkBalance, checkPaused } from '../utils/errorHandler'
import './TransactionTax.css'

function TransactionTax({ web3 }) {
  const [transferAmount, setTransferAmount] = useState('1000')
  const [toAddress, setToAddress] = useState('')
  const [taxInfo, setTaxInfo] = useState(null)
  const [taxRate, setTaxRate] = useState('0')
  const [recentTransactions, setRecentTransactions] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [userBalance, setUserBalance] = useState('0')
  const [isPaused, setIsPaused] = useState(false)

  useEffect(() => {
    if (web3.contract && web3.account) {
      loadTaxInfo()
      loadUserBalance()
      checkPauseStatus()
      const interval = setInterval(() => {
        loadTaxInfo()
        loadUserBalance()
        checkPauseStatus()
      }, 10000)
      return () => clearInterval(interval)
    }
  }, [web3.contract, web3.account])

  const loadUserBalance = async () => {
    if (!web3.contract || !web3.account) return
    try {
      const balance = await checkBalance(web3.contract, web3.account)
      setUserBalance(formatTokenAmount(balance))
    } catch (err) {
      console.error('Error loading balance:', err)
    }
  }

  const checkPauseStatus = async () => {
    if (!web3.contract) return
    try {
      const paused = await checkPaused(web3.contract)
      setIsPaused(paused)
    } catch (err) {
      console.error('Error checking pause status:', err)
    }
  }

  const loadTaxInfo = async () => {
    if (!web3.contract) return
    try {
      const rate = await web3.contract.taxRateBasisPoints()
      setTaxRate(rate.toString())
      
      if (transferAmount) {
        const amountWei = parseTokenAmount(transferAmount)
        const [taxAmount, netAmount] = await web3.contract.calculateTax(amountWei)
        setTaxInfo({
          taxAmount: formatTokenAmount(taxAmount),
          netAmount: formatTokenAmount(netAmount)
        })
      }
    } catch (err) {
      console.error('Error loading tax info:', err)
    }
  }

  useEffect(() => {
    if (transferAmount && web3.contract) {
      loadTaxInfo()
    }
  }, [transferAmount, web3.contract])

  const handleTransfer = async (e) => {
    e.preventDefault()
    if (!web3.contract || !web3.isConnected) {
      setError('Please connect your wallet')
      return
    }

    if (isPaused) {
      setError('Contract is currently paused. Transfers are disabled.')
      return
    }

    if (!toAddress || !transferAmount) {
      setError('Please fill in all fields')
      return
    }

    setLoading(true)
    setError(null)
    setSuccess(null)

    try {
      const amountWei = parseTokenAmount(transferAmount)
      const balance = await checkBalance(web3.contract, web3.account)
      
      if (amountWei > balance) {
        setError(`Insufficient balance. You have ${formatTokenAmount(balance)} ACTX`)
        setLoading(false)
        return
      }

      const tx = await web3.contract.transfer(toAddress, amountWei)
      setSuccess(`Transaction submitted: ${shortenAddress(tx.hash)}`)
      
      const receipt = await tx.wait()
      const transaction = {
        from: shortenAddress(web3.account),
        to: shortenAddress(toAddress),
        amount: transferAmount,
        taxAmount: taxInfo?.taxAmount || '0',
        netAmount: taxInfo?.netAmount || transferAmount,
        timestamp: new Date().toLocaleTimeString(),
        txHash: receipt.hash
      }
      setRecentTransactions([transaction, ...recentTransactions].slice(0, 10))
      
      setToAddress('')
      setTransferAmount('1000')
      await loadUserBalance()
    } catch (err) {
      setError(parseError(err))
      console.error('Error transferring tokens:', err)
    } finally {
      setLoading(false)
    }
  }

  if (!web3.isConnected) {
    return (
      <div className="transaction-tax">
        <div className="connect-prompt">
          <h2>CONNECT WALLET</h2>
          <p>Connect your wallet to test transaction tax</p>
          <button className="connect-btn-large" onClick={web3.connectWallet}>
            CONNECT WALLET
          </button>
        </div>
      </div>
    )
  }

  const taxRatePercent = (Number(taxRate) / 100).toFixed(2)

  return (
    <div className="transaction-tax">
      <div className="section-header">
        <h2>TRANSACTION TAX MECHANISM</h2>
        <p>{taxRatePercent}% recycling tax ensures sustainable tokenomics</p>
      </div>

      {web3.isConnected && (
        <div className="balance-info">
          Your Balance: {userBalance} ACTX
        </div>
      )}

      {isPaused && (
        <div className="alert error">
          ⚠️ Contract is currently paused. Transfers are disabled.
        </div>
      )}

      {error && <div className="alert error">{error}</div>}
      {success && <div className="alert success">{success}</div>}

      <div className="tax-visualization">
        <div className="tax-flow">
          <div className="flow-item">
            <div className="flow-label">Transfer Amount</div>
            <div className="flow-value">{parseFloat(transferAmount || 0).toLocaleString()} ACTX</div>
          </div>
          <div className="flow-arrow-large">↓</div>
          <div className="flow-split">
            <div className="flow-item tax-item">
              <div className="flow-label">Tax ({taxRatePercent}%)</div>
              <div className="flow-value tax-value">{taxInfo?.taxAmount || '0.00'} ACTX</div>
              <div className="flow-destination">→ Reservoir</div>
            </div>
            <div className="flow-item net-item">
              <div className="flow-label">Net Amount</div>
              <div className="flow-value net-value">{taxInfo?.netAmount || '0.00'} ACTX</div>
              <div className="flow-destination">→ Recipient</div>
            </div>
          </div>
        </div>
      </div>

      <div className="tax-simulator">
        <h3>TRANSFER SIMULATOR</h3>
        <form className="simulator-form" onSubmit={handleTransfer}>
          <div className="form-group">
            <label>To Address</label>
            <input
              type="text"
              value={toAddress}
              onChange={(e) => setToAddress(e.target.value)}
              placeholder="0x..."
              required
              disabled={loading}
            />
          </div>
          <div className="form-group">
            <label>Amount (ACTX)</label>
            <input
              type="number"
              value={transferAmount}
              onChange={(e) => setTransferAmount(e.target.value)}
              placeholder="1000"
              min="0"
              step="0.01"
              required
              disabled={loading}
            />
          </div>
          <button type="submit" className="simulate-btn" disabled={loading}>
            {loading ? 'PROCESSING...' : 'EXECUTE TRANSFER'}
          </button>
        </form>
      </div>

      <div className="tax-info">
        <div className="info-card">
          <h4>Tax Configuration</h4>
          <div className="info-item">
            <span>Current Rate:</span>
            <span className="info-value">{taxRatePercent}%</span>
          </div>
          <div className="info-item">
            <span>Maximum Rate:</span>
            <span className="info-value">10%</span>
          </div>
          <div className="info-item">
            <span>Reservoir Address:</span>
            <span className="info-value">{web3.contract ? 'Loading...' : '0xBEb2...F427'}</span>
          </div>
        </div>

        <div className="info-card">
          <h4>Tax Exemptions</h4>
          <div className="exempt-list">
            <div className="exempt-item">✓ Treasury</div>
            <div className="exempt-item">✓ Reservoir</div>
            <div className="exempt-item">✓ Contract</div>
          </div>
        </div>

        <div className="info-card">
          <h4>Circular Economy</h4>
          <div className="economy-flow">
            <div>Tax Collected</div>
            <div>→</div>
            <div>Reservoir</div>
            <div>→</div>
            <div>Reward Pool</div>
            <div>→</div>
            <div>Rewards Distributed</div>
          </div>
        </div>
      </div>

      <div className="recent-transactions">
        <h3>RECENT TRANSACTIONS</h3>
        <div className="transactions-list">
          {recentTransactions.length === 0 ? (
            <p className="empty-state">No transactions yet</p>
          ) : (
            recentTransactions.map((tx, index) => (
              <div key={index} className="transaction-item">
                <div className="tx-header">
                  <a 
                    href={`https://sepolia.etherscan.io/tx/${tx.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="tx-link"
                  >
                    {tx.txHash.slice(0, 20)}...
                  </a>
                  <span className="tx-time">{tx.timestamp}</span>
                </div>
                <div className="tx-details">
                  <div className="tx-addresses">
                    <span>From: {tx.from}</span>
                    <span>To: {tx.to}</span>
                  </div>
                  <div className="tx-amounts">
                    <div className="amount-row">
                      <span>Amount:</span>
                      <span>{tx.amount} ACTX</span>
                    </div>
                    <div className="amount-row tax-row">
                      <span>Tax ({taxRatePercent}%):</span>
                      <span>-{tx.taxAmount} ACTX</span>
                    </div>
                    <div className="amount-row net-row">
                      <span>Net:</span>
                      <span>{tx.netAmount} ACTX</span>
                    </div>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

export default TransactionTax
