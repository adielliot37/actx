import { useState, useEffect } from 'react'
import { ethers } from 'ethers'
import { getProvider, CONTRACT_ADDRESSES, ACTX_TOKEN_ABI, SEPOLIA_CHAIN_ID } from '../utils/contracts'

export function useWeb3() {
  const [account, setAccount] = useState(null)
  const [provider, setProvider] = useState(null)
  const [signer, setSigner] = useState(null)
  const [contract, setContract] = useState(null)
  const [chainId, setChainId] = useState(null)
  const [isConnecting, setIsConnecting] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (typeof window !== 'undefined' && window.ethereum) {
      const initProvider = new ethers.BrowserProvider(window.ethereum)
      setProvider(initProvider)

      window.ethereum.on('accountsChanged', handleAccountsChanged)
      window.ethereum.on('chainChanged', handleChainChanged)

      checkConnection()
    }
  }, [])

  const checkConnection = async () => {
    if (typeof window !== 'undefined' && window.ethereum) {
      try {
        const accounts = await window.ethereum.request({ method: 'eth_accounts' })
        if (accounts.length > 0) {
          await connectWallet()
        }
      } catch (err) {
        console.error('Error checking connection:', err)
      }
    }
  }

  const handleAccountsChanged = (accounts) => {
    if (accounts.length === 0) {
      setAccount(null)
      setSigner(null)
      setContract(null)
    } else {
      connectWallet()
    }
  }

  const handleChainChanged = () => {
    window.location.reload()
  }

  const connectWallet = async () => {
    setIsConnecting(true)
    setError(null)

    try {
      if (typeof window === 'undefined' || !window.ethereum) {
        throw new Error('MetaMask not installed')
      }

      const provider = new ethers.BrowserProvider(window.ethereum)
      const accounts = await provider.send('eth_requestAccounts', [])
      const network = await provider.getNetwork()

      if (Number(network.chainId) !== SEPOLIA_CHAIN_ID) {
        try {
          await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${SEPOLIA_CHAIN_ID.toString(16)}` }]
          })
        } catch (switchError) {
          if (switchError.code === 4902) {
            await window.ethereum.request({
              method: 'wallet_addEthereumChain',
              params: [{
                chainId: `0x${SEPOLIA_CHAIN_ID.toString(16)}`,
                chainName: 'Sepolia Testnet',
                nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
                rpcUrls: ['https://sepolia.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161'],
                blockExplorerUrls: ['https://sepolia.etherscan.io']
              }]
            })
          } else {
            throw switchError
          }
        }
      }

      const signer = await provider.getSigner()
      const contract = new ethers.Contract(CONTRACT_ADDRESSES.ACTX_TOKEN_PROXY, ACTX_TOKEN_ABI, signer)

      setProvider(provider)
      setSigner(signer)
      setContract(contract)
      setAccount(accounts[0])
      setChainId(Number(network.chainId))
    } catch (err) {
      setError(err.message)
      console.error('Error connecting wallet:', err)
    } finally {
      setIsConnecting(false)
    }
  }

  const disconnect = () => {
    setAccount(null)
    setSigner(null)
    setContract(null)
    setChainId(null)
  }

  return {
    account,
    provider,
    signer,
    contract,
    chainId,
    isConnecting,
    error,
    connectWallet,
    disconnect,
    isConnected: !!account && !!contract
  }
}

