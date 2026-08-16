export interface CurrentUser {
  user_id: number;
  username: string;
  employee_id: number | null;
  roles: string[];
  scope_types: string[];
  permissions: string[];
}

export interface Employee {
  employee_id: number;
  full_name: string;
  job_title: string;
  email: string;
  hire_date: string;
  department_id: number;
  department_name: string;
  section_id: number | null;
  section_name: string | null;
  location_id: number;
  location_name: string;
  manager_id: number | null;
  manager_name: string | null;
  is_active: boolean;
}

export interface EmployeeUpdate {
  full_name?: string;
  job_title?: string;
  email?: string;
  department_id?: number;
  section_id?: number | null;
  manager_id?: number | null;
}

export interface AssignableOption {
  id: number;
  name: string;
}

export interface Department {
  department_id: number;
  department_name: string;
  location_id: number;
  location_name: string;
}

export interface Section {
  section_id: number;
  section_name: string;
  department_id: number;
  department_name: string;
}

export interface Location {
  location_id: number;
  location_name: string;
}

export interface Payroll {
  payroll_id: number;
  employee_id: number;
  employee_name: string;
  department_name: string;
  pay_period: string;
  base_salary: string;
  bonus: string;
  deductions: string;
  net_pay: string;
}

export interface LeaveRequest {
  leave_request_id: number;
  employee_id: number;
  employee_name: string;
  start_date: string;
  end_date: string;
  leave_type: string;
  status: string;
  requested_at: string;
}
