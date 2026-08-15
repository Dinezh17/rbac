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
  department_name: string;
  location_name: string;
  manager_name: string | null;
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
