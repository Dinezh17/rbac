> We need to design role-based access control with data scope for an HRMS
> that has a complex database schema. The backend and frontend are already
> built — 200,000+ lines of code — so implementation should be simple.
> We have very complex joins in many queries. Start with an approach,
> brainstorm ideas, analyze common RBAC practice.

Follow-up ask that produced this repo:

> Show this with an implemented app in FastAPI

* Existing system is large and already in production.** ~200k+ LOC
  across backend and frontend. Any real-world adoption of this pattern
  must be **additive and low-invasion** — we are NOT rewriting the
  existing query layer.
* **Many existing queries are complex, multi-table joins.** The scope
  -enforcement mechanism must not require rewriting each join by hand.
  It must be injectable at a small number of well-known points (ideally
  one line per query, or zero lines if pushed to the DB layer).

  now backend stack is python fastapi sql server (mssql) and front end react ts

  we need a great implementation of RBAC that can be used in a production

  with satisfying performance and requirements 100 percent