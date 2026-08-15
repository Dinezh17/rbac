import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { api, login as apiLogin, ApiError } from "../api/client";
import type { CurrentUser } from "../types";

interface AuthContextValue {
  user: CurrentUser | null;
  loading: boolean;
  error: string | null;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  hasPermission: (code: string) => boolean;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const token = localStorage.getItem("access_token");
    if (!token) {
      setLoading(false);
      return;
    }
    api
      .me()
      .then(setUser)
      .catch(() => localStorage.removeItem("access_token"))
      .finally(() => setLoading(false));
  }, []);

  async function login(username: string, password: string) {
    setError(null);
    try {
      const token = await apiLogin(username, password);
      localStorage.setItem("access_token", token);
      const me = await api.me();
      setUser(me);
    } catch (err) {
      const message = err instanceof ApiError ? err.message : "Login failed";
      setError(message);
      throw err;
    }
  }

  function logout() {
    localStorage.removeItem("access_token");
    setUser(null);
  }

  function hasPermission(code: string) {
    return user?.permissions.includes(code) ?? false;
  }

  return (
    <AuthContext.Provider value={{ user, loading, error, login, logout, hasPermission }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
