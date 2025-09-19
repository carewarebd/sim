import React, { useState, useEffect } from 'react';
import { format, subDays, startOfDay, endOfDay } from 'date-fns';

// Types
interface DailySalesData {
  date: string;
  totalOrders: number;
  totalRevenue: number;
  totalItemsSold: number;
  avgOrderValue: number;
  topSellingProduct?: {
    id: string;
    name: string;
    quantitySold: number;
  };
}

interface LowStockProduct {
  id: string;
  name: string;
  sku: string;
  currentStock: number;
  minimumLevel: number;
  lastRestocked: string;
}

interface RecentOrder {
  id: string;
  orderNumber: string;
  customerName: string;
  totalAmount: number;
  status: 'pending' | 'confirmed' | 'processing' | 'shipped' | 'delivered';
  createdAt: string;
}

interface KPICardProps {
  title: string;
  value: string | number;
  change?: string;
  changeType?: 'increase' | 'decrease' | 'neutral';
  icon: React.ReactNode;
  loading?: boolean;
}

// API functions
const fetchDailySales = async (date: string): Promise<DailySalesData> => {
  const response = await fetch(`/api/v1/reports/daily-sales?date=${date}`, {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
    },
  });
  
  if (!response.ok) {
    throw new Error('Failed to fetch daily sales');
  }
  
  return response.json();
};

const fetchLowStockProducts = async (): Promise<{ products: LowStockProduct[] }> => {
  const response = await fetch('/api/v1/inventory/low-stock?limit=5', {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
    },
  });
  
  if (!response.ok) {
    throw new Error('Failed to fetch low stock products');
  }
  
  return response.json();
};

const fetchRecentOrders = async (): Promise<{ orders: RecentOrder[] }> => {
  const response = await fetch('/api/v1/orders?limit=10&sort=created_at&order=desc', {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
    },
  });
  
  if (!response.ok) {
    throw new Error('Failed to fetch recent orders');
  }
  
  return response.json();
};

// KPI Card Component
const KPICard: React.FC<KPICardProps> = ({ 
  title, 
  value, 
  change, 
  changeType = 'neutral', 
  icon, 
  loading = false 
}) => {
  const changeColorClasses = {
    increase: 'text-green-600 bg-green-100',
    decrease: 'text-red-600 bg-red-100',
    neutral: 'text-gray-600 bg-gray-100',
  };

  return (
    <div className="bg-white overflow-hidden shadow-sm rounded-lg border border-gray-200">
      <div className="p-6">
        <div className="flex items-center">
          <div className="flex-shrink-0">
            <div className="w-8 h-8 text-gray-400">
              {icon}
            </div>
          </div>
          <div className="ml-5 w-0 flex-1">
            <dl>
              <dt className="text-sm font-medium text-gray-500 truncate">
                {title}
              </dt>
              <dd className="flex items-baseline">
                {loading ? (
                  <div className="animate-pulse bg-gray-200 h-8 w-20 rounded"></div>
                ) : (
                  <>
                    <div className="text-2xl font-semibold text-gray-900">
                      {typeof value === 'number' && title.includes('$') 
                        ? `$${value.toLocaleString('en-US', { minimumFractionDigits: 2 })}`
                        : value.toLocaleString()
                      }
                    </div>
                    {change && (
                      <div className={`ml-2 flex items-baseline text-sm font-semibold ${changeColorClasses[changeType]}`}>
                        <span className="sr-only">
                          {changeType === 'increase' ? 'Increased' : changeType === 'decrease' ? 'Decreased' : 'Changed'} by
                        </span>
                        {change}
                      </div>
                    )}
                  </>
                )}
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
  );
};

// Main Dashboard Component
const DashboardOwner: React.FC = () => {
  const [todaySales, setTodaySales] = useState<DailySalesData | null>(null);
  const [yesterdaySales, setYesterdaySales] = useState<DailySalesData | null>(null);
  const [lowStockProducts, setLowStockProducts] = useState<LowStockProduct[]>([]);
  const [recentOrders, setRecentOrders] = useState<RecentOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadDashboardData();
  }, []);

  const loadDashboardData = async () => {
    try {
      setLoading(true);
      setError(null);

      const today = format(new Date(), 'yyyy-MM-dd');
      const yesterday = format(subDays(new Date(), 1), 'yyyy-MM-dd');

      // Fetch all data in parallel
      const [
        todayData,
        yesterdayData,
        lowStockData,
        ordersData,
      ] = await Promise.all([
        fetchDailySales(today),
        fetchDailySales(yesterday),
        fetchLowStockProducts(),
        fetchRecentOrders(),
      ]);

      setTodaySales(todayData);
      setYesterdaySales(yesterdayData);
      setLowStockProducts(lowStockData.products);
      setRecentOrders(ordersData.orders);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load dashboard data');
    } finally {
      setLoading(false);
    }
  };

  const calculateChange = (current: number, previous: number): { change: string; type: 'increase' | 'decrease' | 'neutral' } => {
    if (previous === 0) {
      return { change: 'N/A', type: 'neutral' };
    }
    
    const percentChange = ((current - previous) / previous) * 100;
    const type = percentChange > 0 ? 'increase' : percentChange < 0 ? 'decrease' : 'neutral';
    const change = `${percentChange > 0 ? '+' : ''}${percentChange.toFixed(1)}%`;
    
    return { change, type };
  };

  const getStatusBadgeColor = (status: RecentOrder['status']) => {
    const colors = {
      pending: 'bg-yellow-100 text-yellow-800',
      confirmed: 'bg-blue-100 text-blue-800',
      processing: 'bg-purple-100 text-purple-800',
      shipped: 'bg-indigo-100 text-indigo-800',
      delivered: 'bg-green-100 text-green-800',
    };
    return colors[status] || 'bg-gray-100 text-gray-800';
  };

  if (error) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="text-red-500 text-xl mb-4">Failed to load dashboard</div>
          <p className="text-gray-600 mb-4">{error}</p>
          <button
            onClick={loadDashboardData}
            className="bg-primary-600 text-white px-4 py-2 rounded-md hover:bg-primary-700"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  const revenueChange = todaySales && yesterdaySales 
    ? calculateChange(todaySales.totalRevenue, yesterdaySales.totalRevenue)
    : { change: 'N/A', type: 'neutral' as const };

  const ordersChange = todaySales && yesterdaySales 
    ? calculateChange(todaySales.totalOrders, yesterdaySales.totalOrders)
    : { change: 'N/A', type: 'neutral' as const };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="py-6">
            <h1 className="text-3xl font-bold text-gray-900">Dashboard</h1>
            <p className="mt-1 text-sm text-gray-600">
              Welcome back! Here's what's happening with your business today.
            </p>
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* KPI Cards */}
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8">
          <KPICard
            title="Today's Revenue"
            value={todaySales?.totalRevenue ?? 0}
            change={revenueChange.change}
            changeType={revenueChange.type}
            loading={loading}
            icon={
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
              </svg>
            }
          />

          <KPICard
            title="Today's Orders"
            value={todaySales?.totalOrders ?? 0}
            change={ordersChange.change}
            changeType={ordersChange.type}
            loading={loading}
            icon={
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
              </svg>
            }
          />

          <KPICard
            title="Items Sold Today"
            value={todaySales?.totalItemsSold ?? 0}
            loading={loading}
            icon={
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
              </svg>
            }
          />

          <KPICard
            title="Avg Order Value"
            value={todaySales?.avgOrderValue ?? 0}
            loading={loading}
            icon={
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
            }
          />
        </div>

        <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
          {/* Low Stock Alerts */}
          <div className="bg-white shadow-sm rounded-lg border border-gray-200">
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-lg font-semibold text-gray-900">Low Stock Alerts</h2>
              <p className="text-sm text-gray-600">Products that need restocking</p>
            </div>
            <div className="divide-y divide-gray-200">
              {loading ? (
                <div className="p-6">
                  {[...Array(3)].map((_, i) => (
                    <div key={i} className="animate-pulse flex space-x-4 mb-4">
                      <div className="rounded bg-gray-200 h-4 w-1/4"></div>
                      <div className="rounded bg-gray-200 h-4 w-1/6"></div>
                      <div className="rounded bg-gray-200 h-4 w-1/6"></div>
                    </div>
                  ))}
                </div>
              ) : lowStockProducts.length > 0 ? (
                lowStockProducts.map((product) => (
                  <div key={product.id} className="px-6 py-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-900">{product.name}</p>
                        <p className="text-sm text-gray-500">SKU: {product.sku}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-medium text-red-600">
                          {product.currentStock} / {product.minimumLevel}
                        </p>
                        <p className="text-xs text-gray-500">
                          Last restocked: {format(new Date(product.lastRestocked), 'MMM d')}
                        </p>
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="px-6 py-8 text-center">
                  <p className="text-gray-500">All products are well stocked!</p>
                </div>
              )}
            </div>
            <div className="px-6 py-3 bg-gray-50 text-right">
              <button className="text-sm font-medium text-primary-600 hover:text-primary-500">
                View all inventory →
              </button>
            </div>
          </div>

          {/* Recent Orders */}
          <div className="bg-white shadow-sm rounded-lg border border-gray-200">
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-lg font-semibold text-gray-900">Recent Orders</h2>
              <p className="text-sm text-gray-600">Latest customer orders</p>
            </div>
            <div className="divide-y divide-gray-200">
              {loading ? (
                <div className="p-6">
                  {[...Array(5)].map((_, i) => (
                    <div key={i} className="animate-pulse flex justify-between items-center py-3">
                      <div>
                        <div className="bg-gray-200 h-4 w-24 rounded mb-1"></div>
                        <div className="bg-gray-200 h-3 w-32 rounded"></div>
                      </div>
                      <div className="bg-gray-200 h-6 w-16 rounded"></div>
                    </div>
                  ))}
                </div>
              ) : recentOrders.length > 0 ? (
                recentOrders.slice(0, 8).map((order) => (
                  <div key={order.id} className="px-6 py-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-900">
                          #{order.orderNumber}
                        </p>
                        <p className="text-sm text-gray-500">{order.customerName}</p>
                        <p className="text-xs text-gray-400">
                          {format(new Date(order.createdAt), 'MMM d, h:mm a')}
                        </p>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-medium text-gray-900">
                          ${order.totalAmount.toFixed(2)}
                        </p>
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getStatusBadgeColor(order.status)}`}>
                          {order.status}
                        </span>
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="px-6 py-8 text-center">
                  <p className="text-gray-500">No recent orders</p>
                </div>
              )}
            </div>
            <div className="px-6 py-3 bg-gray-50 text-right">
              <button className="text-sm font-medium text-primary-600 hover:text-primary-500">
                View all orders →
              </button>
            </div>
          </div>
        </div>

        {/* Quick Actions */}
        <div className="mt-8 bg-white shadow-sm rounded-lg border border-gray-200">
          <div className="px-6 py-4 border-b border-gray-200">
            <h2 className="text-lg font-semibold text-gray-900">Quick Actions</h2>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <button className="flex flex-col items-center p-4 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors">
                <svg className="w-8 h-8 text-primary-600 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                <span className="text-sm font-medium text-gray-900">Add Product</span>
              </button>
              
              <button className="flex flex-col items-center p-4 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors">
                <svg className="w-8 h-8 text-primary-600 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
                </svg>
                <span className="text-sm font-medium text-gray-900">New Order</span>
              </button>
              
              <button className="flex flex-col items-center p-4 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors">
                <svg className="w-8 h-8 text-primary-600 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
                <span className="text-sm font-medium text-gray-900">View Reports</span>
              </button>
              
              <button className="flex flex-col items-center p-4 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors">
                <svg className="w-8 h-8 text-primary-600 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                </svg>
                <span className="text-sm font-medium text-gray-900">Invite User</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default DashboardOwner;