import type { ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

export function ProtectedRoute({
  children,
  requirePermission,
}: {
  children: ReactNode;
  requirePermission?: string;
}) {
  const { user, loading, hasPermission } = useAuth();

  if (loading) return <div className="page-loading">Loading…</div>;
  if (!user) return <Navigate to="/login" replace />;
  if (requirePermission && !hasPermission(requirePermission)) {
    return (
      <div className="empty-state">
        Your role does not include the "{requirePermission}" permission.
      </div>
    );
  }
  return <>{children}</>;
}
