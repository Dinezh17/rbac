import type {
  AssignableOption,
  CurrentUser,
  Department,
  Employee,
  EmployeeUpdate,
  LeaveRequest,
  Location,
  Payroll,
  Section,
} from "../types";

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL as string;

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function getToken(): string | null {
  return localStorage.getItem("access_token");
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    ...(options.body ? { "Content-Type": "application/json" } : {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };

  const res = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });

  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      detail = body.detail ?? detail;
    } catch {
      // ignore non-JSON error bodies
    }
    throw new ApiError(res.status, detail);
  }

  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export async function login(username: string, password: string): Promise<string> {
  const body = new URLSearchParams({ username, password });
  const res = await fetch(`${API_BASE_URL}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    let detail = "Invalid username or password";
    try {
      const data = await res.json();
      detail = data.detail ?? detail;
    } catch {
      // ignore
    }
    throw new ApiError(res.status, detail);
  }
  const data = await res.json();
  return data.access_token as string;
}

export const api = {
  me: () => request<CurrentUser>("/auth/me"),

  employees: () => request<Employee[]>("/employees"),
  updateEmployee: (id: number, payload: EmployeeUpdate) =>
    request<Employee>(`/employees/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),

  payroll: () => request<Payroll[]>("/payroll"),

  leaveRequests: () => request<LeaveRequest[]>("/leave"),
  createLeaveRequest: (payload: { start_date: string; end_date: string; leave_type: string }) =>
    request<LeaveRequest>("/leave", { method: "POST", body: JSON.stringify(payload) }),
  approveLeaveRequest: (id: number) => request<LeaveRequest>(`/leave/${id}/approve`, { method: "PATCH" }),

  departments: () => request<Department[]>("/departments"),
  assignableDepartments: () => request<AssignableOption[]>("/departments/assignable"),
  createDepartment: (payload: { department_name: string; location_id: number }) =>
    request<Department>("/departments", { method: "POST", body: JSON.stringify(payload) }),
  updateDepartment: (id: number, payload: { department_name?: string; location_id?: number }) =>
    request<Department>(`/departments/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteDepartment: (id: number) => request<void>(`/departments/${id}`, { method: "DELETE" }),

  sections: () => request<Section[]>("/sections"),
  assignableSections: () => request<AssignableOption[]>("/sections/assignable"),
  createSection: (payload: { section_name: string; department_id: number }) =>
    request<Section>("/sections", { method: "POST", body: JSON.stringify(payload) }),
  updateSection: (id: number, payload: { section_name?: string; department_id?: number }) =>
    request<Section>(`/sections/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deleteSection: (id: number) => request<void>(`/sections/${id}`, { method: "DELETE" }),

  locations: () => request<Location[]>("/locations"),
};
