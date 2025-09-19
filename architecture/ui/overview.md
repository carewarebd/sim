# UI Design Overview

## Design System

### Color Palette
```css
:root {
  /* Primary Colors */
  --primary-50: #eff6ff;
  --primary-100: #dbeafe;
  --primary-500: #3b82f6;  /* Main brand color */
  --primary-600: #2563eb;
  --primary-700: #1d4ed8;
  
  /* Secondary Colors */
  --secondary-500: #10b981;
  --secondary-600: #059669;
  
  /* Accent Colors */
  --accent-500: #ef4444;
  --accent-600: #dc2626;
  
  /* Neutral Colors */
  --gray-50: #f9fafb;
  --gray-100: #f3f4f6;
  --gray-200: #e5e7eb;
  --gray-500: #6b7280;
  --gray-700: #374151;
  --gray-900: #111827;
}
```

### Typography Scale
```css
.text-xs { font-size: 0.75rem; }
.text-sm { font-size: 0.875rem; }
.text-base { font-size: 1rem; }
.text-lg { font-size: 1.125rem; }
.text-xl { font-size: 1.25rem; }
.text-2xl { font-size: 1.5rem; }
.text-3xl { font-size: 1.875rem; }
```

### Spacing Scale
- Base unit: 0.25rem (4px)
- Standard spacing: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64 (px)

### Component Sizes
- **Buttons**: Small (32px), Medium (40px), Large (48px)
- **Input Fields**: Small (32px), Medium (40px), Large (48px)
- **Cards**: Standard padding 24px, Small padding 16px

## Navigation Structure

### Primary Navigation (Sidebar)
```
📊 Dashboard
📦 Products
   ├─ Product List
   ├─ Add Product
   └─ Categories
📋 Inventory
   ├─ Stock Levels
   ├─ Adjustments
   └─ Low Stock Alerts
🛒 Orders
   ├─ All Orders
   ├─ Pending Orders
   └─ Order History
📊 Reports
   ├─ Sales Reports
   ├─ Inventory Reports
   └─ Performance Reports
📄 Invoices
🔔 Notifications
⚙️ Settings
```

### User Role Visibility

#### Owner/Admin Access
- Full access to all pages
- User management capabilities
- Financial reports and settings
- Tenant configuration

#### Salesperson Access  
- Dashboard (limited KPIs)
- Products (view/edit assigned)
- Orders (create/view/update)
- Own performance reports
- Customer management

#### Viewer Access
- Dashboard (read-only)
- Products (view-only)
- Orders (view-only)
- Reports (limited access)

## Page Specifications

### 1. Login Page (`Login.tsx`)
- **Purpose**: User authentication
- **API Calls**: `POST /auth/signin`
- **Features**:
  - Email/password form
  - Remember me checkbox
  - Forgot password link
  - Tenant selection (if multi-tenant user)
- **States**: loading, error, success
- **Validation**: Email format, required fields

### 2. Owner Dashboard (`DashboardOwner.tsx`)
- **Purpose**: High-level business metrics and quick actions
- **API Calls**: 
  - `GET /reports/daily-sales`
  - `GET /inventory/low-stock` 
  - `GET /orders?status=pending`
  - `GET /notifications?unreadOnly=true`
- **Features**:
  - KPI cards (today's sales, monthly revenue, orders)
  - Sales trend chart (last 30 days)
  - Low stock alerts
  - Recent orders
  - Quick action buttons
- **Real-time Updates**: WebSocket for order notifications

### 3. Products List (`ProductsList.tsx`)
- **Purpose**: Product catalog management
- **API Calls**: 
  - `GET /products`
  - `PATCH /products/{id}` (quick status toggle)
  - `DELETE /products/{id}`
- **Features**:
  - Searchable/filterable product grid
  - Bulk actions (activate/deactivate)
  - Quick edit inline
  - Image thumbnails
  - Stock level indicators
  - Export to CSV

### 4. Product Editor (`ProductEditor.tsx`)
- **Purpose**: Create/edit individual products
- **API Calls**:
  - `POST /products` (create)
  - `PUT /products/{id}` (update)
  - `GET /products/{id}` (load existing)
  - `POST /products/{id}/images/upload-url` (image upload)
- **Features**:
  - Multi-step form (basic info, pricing, inventory, images)
  - Image upload with preview
  - Rich text editor for description
  - Category selection
  - SEO fields (slug, meta description)
  - Inventory management integration

### 5. Inventory Management (`Inventory.tsx`)
- **Purpose**: Stock level management and adjustments
- **API Calls**:
  - `GET /inventory/low-stock`
  - `POST /inventory/adjust`
  - `GET /products?inStock=false`
- **Features**:
  - Stock adjustment forms
  - Low stock alerts dashboard
  - Bulk stock updates
  - Transfer between locations
  - Inventory history tracking
  - Stock level charts

### 6. Orders Management (`Orders.tsx`)
- **Purpose**: Order processing and management
- **API Calls**:
  - `GET /orders`
  - `GET /orders/{id}`
  - `PATCH /orders/{id}` (status updates)
  - `POST /orders` (manual order creation)
- **Features**:
  - Order list with filters
  - Order status workflow
  - Customer information panel
  - Order timeline/notes
  - Print order receipts
  - Refund processing

### 7. Public Marketplace (`PublicMarketplace.tsx`)
- **Purpose**: Customer-facing product search and ordering
- **API Calls**:
  - `GET /marketplace/search`
  - `GET /marketplace/shops/nearby`
  - `POST /marketplace/orders`
- **Features**:
  - Product search with filters
  - Geolocation-based shop finder
  - Interactive map with shop locations
  - Product detail modals
  - Shopping cart functionality
  - Checkout process

### 8. Invoice Viewer (`InvoiceViewer.tsx`)
- **Purpose**: Invoice generation and PDF viewing
- **API Calls**:
  - `GET /invoices`
  - `GET /invoices/{id}`
  - `POST /invoices/{id}/generate-pdf`
- **Features**:
  - Invoice list with search
  - PDF preview in browser
  - Email invoice to customer
  - Print invoice
  - Invoice templates
  - Payment status tracking

## Component Architecture

### Shared Components

#### Layout Components
```typescript
// MainLayout.tsx - App shell with sidebar and header
interface MainLayoutProps {
  children: React.ReactNode;
  user: User;
  notifications: Notification[];
}

// Sidebar.tsx - Navigation sidebar
interface SidebarProps {
  currentPath: string;
  userRole: UserRole;
}

// Header.tsx - Top bar with user menu and notifications
interface HeaderProps {
  user: User;
  notificationCount: number;
}
```

#### UI Components
```typescript
// Button.tsx - Reusable button component
interface ButtonProps {
  variant: 'primary' | 'secondary' | 'outline' | 'ghost';
  size: 'sm' | 'md' | 'lg';
  loading?: boolean;
  disabled?: boolean;
}

// Modal.tsx - Modal dialog component
interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  size: 'sm' | 'md' | 'lg' | 'xl';
}

// DataTable.tsx - Sortable, filterable table
interface DataTableProps<T> {
  data: T[];
  columns: ColumnDef<T>[];
  pagination?: PaginationOptions;
  loading?: boolean;
}
```

#### Form Components
```typescript
// FormField.tsx - Form input wrapper with validation
interface FormFieldProps {
  label: string;
  error?: string;
  required?: boolean;
  helpText?: string;
}

// SearchInput.tsx - Debounced search input
interface SearchInputProps {
  onSearch: (query: string) => void;
  placeholder: string;
  delay?: number;
}
```

### State Management

#### API State
```typescript
// Use React Query for API state management
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

// Example: Products query hook
export const useProducts = (filters: ProductFilters) => {
  return useQuery({
    queryKey: ['products', filters],
    queryFn: () => api.getProducts(filters),
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
};

// Example: Create product mutation
export const useCreateProduct = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: api.createProduct,
    onSuccess: () => {
      queryClient.invalidateQueries(['products']);
    },
  });
};
```

#### Local State
```typescript
// Use Zustand for global app state
interface AppStore {
  user: User | null;
  tenant: Tenant | null;
  sidebarCollapsed: boolean;
  
  setUser: (user: User) => void;
  setTenant: (tenant: Tenant) => void;
  toggleSidebar: () => void;
}

export const useAppStore = create<AppStore>((set) => ({
  user: null,
  tenant: null,
  sidebarCollapsed: false,
  
  setUser: (user) => set({ user }),
  setTenant: (tenant) => set({ tenant }),
  toggleSidebar: () => set((state) => ({ 
    sidebarCollapsed: !state.sidebarCollapsed 
  })),
}));
```

## Responsive Design

### Breakpoints
```css
/* Mobile First Approach */
.container {
  width: 100%;
  padding: 0 1rem;
}

/* Tablet: 768px+ */
@media (min-width: 768px) {
  .container {
    max-width: 768px;
    padding: 0 2rem;
  }
}

/* Desktop: 1024px+ */  
@media (min-width: 1024px) {
  .container {
    max-width: 1024px;
  }
}

/* Large Desktop: 1280px+ */
@media (min-width: 1280px) {
  .container {
    max-width: 1280px;
  }
}
```

### Mobile Adaptations
- **Sidebar**: Converts to bottom navigation or hamburger menu
- **Tables**: Horizontal scroll or card layout
- **Forms**: Stack fields vertically
- **Charts**: Simplified view with key metrics only

## Accessibility Standards

### WCAG 2.1 AA Compliance
- **Color Contrast**: Minimum 4.5:1 for normal text, 3:1 for large text
- **Keyboard Navigation**: Full keyboard accessibility
- **Screen Reader**: ARIA labels and semantic HTML
- **Focus Management**: Visible focus indicators

### Implementation Guidelines
```typescript
// Example: Accessible button component
interface AccessibleButtonProps {
  'aria-label'?: string;
  'aria-describedby'?: string;
  disabled?: boolean;
}

const Button: React.FC<AccessibleButtonProps> = ({
  children,
  disabled,
  ...ariaProps
}) => {
  return (
    <button
      className={`
        focus:ring-2 focus:ring-primary-500 focus:outline-none
        disabled:opacity-50 disabled:cursor-not-allowed
        ${disabled ? 'aria-disabled' : ''}
      `}
      disabled={disabled}
      {...ariaProps}
    >
      {children}
    </button>
  );
};
```

## Performance Optimization

### Code Splitting
```typescript
// Lazy load page components
const ProductsList = lazy(() => import('./pages/ProductsList'));
const Orders = lazy(() => import('./pages/Orders'));

// Route-based code splitting
<Route 
  path="/products" 
  element={
    <Suspense fallback={<PageLoader />}>
      <ProductsList />
    </Suspense>
  } 
/>
```

### Image Optimization
- WebP format with JPEG fallback
- Responsive images with `srcSet`
- Lazy loading for product images
- CDN delivery via CloudFront

### Bundle Size Targets
- **Initial Bundle**: < 200KB gzipped
- **Route Chunks**: < 100KB gzipped each
- **Vendor Chunks**: React, React-DOM, Router separate

## Error Boundaries

```typescript
// Global error boundary for unhandled errors
class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true };
  }

  componentDidCatch(error, errorInfo) {
    // Log error to monitoring service
    console.error('Application error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return <ErrorFallback />;
    }
    return this.props.children;
  }
}
```

This UI design provides a comprehensive, accessible, and performant user experience optimized for the shop management workflow while maintaining consistency across all user roles and device types.