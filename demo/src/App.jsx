import { useState } from 'react'
import Dashboard from './components/Dashboard'
import RewardDistribution from './components/RewardDistribution'
import TransactionTax from './components/TransactionTax'
import RoleManagement from './components/RoleManagement'
import EventTracking from './components/EventTracking'
import WalletConnect from './components/WalletConnect'
import { useWeb3 } from './hooks/useWeb3'
import './App.css'

function App() {
  const [activeTab, setActiveTab] = useState('dashboard')
  const web3 = useWeb3()

  return (
    <div className="app">
      <header className="header">
        <div className="header-content">
          <h1>ACT.X TOKEN</h1>
          <p>Production-Ready Rewards Token</p>
        </div>
        <div className="header-right">
          <WalletConnect web3={web3} />
          <div className="status-indicator">
            <span className="status-dot"></span>
            <span>{web3.isConnected ? 'CONNECTED' : 'DISCONNECTED'}</span>
          </div>
        </div>
      </header>

      <nav className="nav">
        <button 
          className={activeTab === 'dashboard' ? 'active' : ''}
          onClick={() => setActiveTab('dashboard')}
        >
          Dashboard
        </button>
        <button 
          className={activeTab === 'rewards' ? 'active' : ''}
          onClick={() => setActiveTab('rewards')}
        >
          Reward Distribution
        </button>
        <button 
          className={activeTab === 'tax' ? 'active' : ''}
          onClick={() => setActiveTab('tax')}
        >
          Transaction Tax
        </button>
        <button 
          className={activeTab === 'roles' ? 'active' : ''}
          onClick={() => setActiveTab('roles')}
        >
          Role Management
        </button>
        <button 
          className={activeTab === 'events' ? 'active' : ''}
          onClick={() => setActiveTab('events')}
        >
          Event Tracking
        </button>
      </nav>

      <main className="main">
        {activeTab === 'dashboard' && <Dashboard web3={web3} />}
        {activeTab === 'rewards' && <RewardDistribution web3={web3} />}
        {activeTab === 'tax' && <TransactionTax web3={web3} />}
        {activeTab === 'roles' && <RoleManagement web3={web3} />}
        {activeTab === 'events' && <EventTracking web3={web3} />}
      </main>
    </div>
  )
}

export default App

