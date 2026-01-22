import { Navigate, useLocation } from 'react-router-dom';
import { useAuthStore, User } from '../store/authStore';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredRole?: User['role'];
  requiredPermission?: string;
}

/**
 * ProtectedRoute component that redirects to login if user is not authenticated.
 * Optionally checks for required role or permission.
 */
export function ProtectedRoute({ 
  children, 
  requiredRole, 
  requiredPermission 
}: ProtectedRouteProps) {
  const { isAuthenticated, hasRole, canPerform } = useAuthStore();
  const location = useLocation();

  // If not authenticated, redirect to login
  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  }

  // Check role requirement
  if (requiredRole && !hasRole(requiredRole)) {
    return <Navigate to="/unauthorized" replace />;
  }

  // Check permission requirement
  if (requiredPermission && !canPerform(requiredPermission)) {
    return <Navigate to="/unauthorized" replace />;
  }

  return <>{children}</>;
}

/**
 * PublicRoute component that redirects to dashboard if user is already authenticated.
 * Use for login page, etc.
 */
interface PublicRouteProps {
  children: React.ReactNode;
}

export function PublicRoute({ children }: PublicRouteProps) {
  const { isAuthenticated } = useAuthStore();
  const location = useLocation();

  if (isAuthenticated) {
    // Redirect to the page they were trying to access, or dashboard
    const from = (location.state as { from?: string })?.from || '/';
    return <Navigate to={from} replace />;
  }

  return <>{children}</>;
}

/**
 * Hook to check if current user has required role
 */
export function useRequireRole(role: User['role']): boolean {
  const { hasRole, isAuthenticated } = useAuthStore();
  return isAuthenticated && hasRole(role);
}

/**
 * Hook to check if current user has required permission
 */
export function useRequirePermission(permission: string): boolean {
  const { canPerform, isAuthenticated } = useAuthStore();
  return isAuthenticated && canPerform(permission);
}

export default ProtectedRoute;
