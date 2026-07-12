# Revised Feature List — Admin-Only Operations App (No Photo Uploads)
### Restaurant Stock & Shift Ledger + Hostel Management + Staff Management

---

## CORE DESIGN CHANGE

**Users of this app: 2 roles only.**
- **Super Admin (Owner)** — full access, all locations, all data, settings, audit logs
- **Admin (Manager)** — assigned location(s) only, day-to-day data entry

**No photo uploads anywhere.** All data is text and numbers only. No KYC images, no bill photos, no variance proofs, no room photos, no receipt proofs. This drastically simplifies DPDP compliance and frees up storage quota.

---

# MODULE 1: RESTAURANT — STOCK & SHIFT LEDGER (1–69)

## 1.1 Shift Setup (1–5)
1. Shift definitions: Breakfast, Lunch, Dinner (owner can rename/add a 4th, e.g. Snacks)
2. Shift timing windows per shift (e.g. Breakfast 6:00–11:00)
3. Shift status (open / closed / locked)
4. Shift assignment to an admin (who is responsible for this shift's entries)
5. Shift lock after closing (no edits without Super Admin override — audit-logged)

## 1.2 Shift Income Entry (6–12)
6. Income entry per shift (single total, or broken into line items)
7. Income source breakdown: Dine-in / Parcel / Bulk order / Catering / Other
8. Payment mode split within a shift: Cash / UPI / Card
9. Customer count per shift (optional, for per-head average)
10. Notes field per shift (e.g. "Wedding party of 40")
11. Income entry validation (cannot be negative; warn if wildly out of normal range)
12. Edit income entry (before shift lock; audit-logged)

## 1.3 Shift Expense Entry (13–20)
13. Expense entry per shift
14. Expense categories: Raw material purchase, Gas, Vegetables, Milk, Meat, Staff food, Transport, Repairs, Electricity, Misc
15. Custom expense category creation (Super Admin)
16. Expense line items (description, category, amount, paid-to)
17. Payment mode per expense (Cash / UPI / Credit — pay later)
18. Credit/payable tracking (expense marked "Credit" → shows in pending payables list)
19. Mark payable as settled (with date and mode)
20. Expense edit before lock (audit-logged)

## 1.4 Shift Close & Reconciliation (21–27)
21. Shift close workflow (admin confirms income + expense entries complete)
22. Cash-in-hand reconciliation (opening cash + cash income − cash expense = expected closing cash)
23. Actual closing cash entry (physical count)
24. Variance calculation (expected vs actual) with mandatory reason if mismatch
25. Shift close checklist (income entered ✓, expense entered ✓, stock consumption recorded ✓, cash counted ✓)
26. Shift handover note (message to next shift's admin)
27. Shift P&L snapshot (income − expense for that shift)

## 1.5 Stock Master (28–37)
28. Stock item master (name, category, unit: kg/L/pcs/packet)
29. Stock categories (Grains, Vegetables, Meat, Dairy, Spices, Oil, Gas, Packaging, Cleaning, Beverages)
30. Multiple units per item with conversion (e.g. 1 bag = 25 kg; buy in bags, consume in kg)
31. Item code / SKU (optional, for quick search)
32. Perishable flag + shelf life in days
33. Reorder level (minimum stock threshold) per item
34. Reorder quantity (how much to buy when triggered)
35. Standard/expected rate per unit (to detect overpriced purchases)
36. Preferred supplier link per item
37. Item active/inactive toggle

## 1.6 Purchases & Stock In (38–48)
38. Purchase entry (supplier, date, items, qty, rate, total)
39. Multi-item purchase in a single entry (one bill = many items)
40. Auto-calculate line total and grand total
41. Purchase payment status: Paid / Credit (pending payment)
42. Purchase linked to a shift (so it flows into that shift's expense automatically)
43. Rate variance alert (flag if purchase rate is >X% above the item's standard rate)
44. Purchase return / rejection entry (bad quality goods sent back — reduces stock)
45. Stock auto-increment on purchase entry
46. Purchase history per item (rate trend over time)
47. Purchase history per supplier
48. Duplicate purchase warning (same supplier + same amount + same day)

## 1.7 Consumption & Stock Out (49–56)
49. Consumption entry per shift (what was used in Breakfast / Lunch / Dinner)
50. Quick-entry mode (common items pre-listed with a qty box — fast daily entry)
51. Stock auto-decrement on consumption entry
52. Transfer stock to hostel mess (stock out of restaurant, in to hostel meal cost)
53. Internal issue (staff meals, tastings) — recorded separately from waste
54. Consumption template per shift (e.g. "Breakfast usually consumes: 10kg rice, 5L milk…") — one tap to load, then adjust
55. Negative stock prevention (block or warn if consuming more than available)
56. Consumption history per item (usage trend)

## 1.8 Physical Stock Count & Variance (57–63)
57. Physical stock count entry (periodic — daily/weekly/monthly, configurable)
58. Count sheet generation (list of all items with a blank "actual qty" field, printable)
59. System stock vs physical stock comparison
60. Variance report per item (shortage / excess, with value in ₹)
61. Variance reason capture (pilferage, spillage, measurement error, entry mistake)
62. Stock adjustment posting (system stock corrected to physical; adjustment audit-logged)
63. Shrinkage report (total value of unexplained stock loss per month)

## 1.9 Waste & Spoilage (64–69)
64. Waste entry (item, quantity, date, shift)
65. Waste reason codes (expired, spoiled, over-cooked, customer return, damaged in storage)
66. Auto-decrement stock on waste entry
67. Waste cost calculation (qty × latest purchase rate)
68. Monthly waste report + waste-as-%-of-purchases metric
69. Shift expense summary card (total by category)

## 1.10 Stock Alerts & Intelligence (70–76)
70. Low-stock alert (item below reorder level) — dashboard + WhatsApp to owner
71. Expiry alert (perishable items nearing shelf-life end)
72. Auto-generated purchase list ("what to buy today" — all items below reorder level with suggested qty)
73. Dead-stock report (items not consumed in N days)
74. Fast-moving vs slow-moving item report
75. Stock valuation report (current stock value at latest purchase rate)
76. Consumption forecast (predict next week's needs from historical usage)

## 1.11 Supplier Management (77–83)
77. Supplier master (name, phone, category supplied, address)
78. Supplier contact quick-call / WhatsApp link
79. Purchase history per supplier
80. Outstanding payable per supplier (credit purchases not yet settled)
81. Payment settlement entry against a supplier
82. Supplier rating (quality / punctuality — simple 1–5 by admin)
83. Supplier price comparison (same item, different suppliers, rate comparison)

## 1.12 Restaurant Reports (84–92)
84. Daily report (income, expense, net, by shift)
85. Shift-wise comparison (which shift earns most / costs most)
86. Weekly / monthly income & expense summary
87. Expense breakdown by category (pie/bar)
88. Purchase report (period-wise total purchases, by category, by supplier)
89. Consumption report (item-wise usage over period)
90. Stock movement report (opening + purchases − consumption − waste = closing)
91. Gross margin proxy (income − raw material consumption)
92. Export all reports (CSV / PDF)

---

# MODULE 2: HOSTEL (93–179)

## 2.1 Multi-Location Setup (93–98)
93. Location creation (each hostel; type = hostel)
94. Location details (name, address, phone, admin in charge)
95. Location capacity (total rooms, total beds)
96. Location-specific rent defaults (standard rent, standard deposit)
97. Location active/inactive
98. Location settings per location

## 2.2 Room & Bed Management (99–110)
99. Room creation (room number, floor, capacity)
100. Bed creation within room (bed number/label)
101. Bed-level occupancy tracking
102. Occupancy grid — colour-coded: Vacant / Occupied / Notice period / Maintenance / Reserved
103. Room type (shared dorm / double / single / deluxe) with rent slab
104. Bulk room + bed creation (e.g. "Create rooms 101–120, 4 beds each")
105. Bed assignment / reassignment to tenant
106. Bed transfer (move tenant from one bed/room/hostel to another — history retained)
107. Maintenance mode per bed/room (blocks assignment)
108. Room amenities checklist (AC, attached bath, balcony)
109. Occupancy % per location, live
110. Room type with custom rent

## 2.3 Tenant Records & KYC (111–122)
111. Tenant registration (name, phone, alternate phone, email, DOB, gender)
112. Present address + permanent address
113. Emergency contact (name, relation, phone)
114. Occupation / college / employer (for reference)
115. **Aadhaar: only last 4 digits stored** in DB (full number never stored — DPDP/UIDAI compliance)
116. Document verification status (pending / verified by admin)
117. DPDP consent record (admin confirms tenant agreed to consent; timestamp stored)
118. Joining date / check-in date
119. Rent amount + deposit amount for this tenant
120. Notice period (days) for this tenant
121. Tenant status (active / notice period / vacated / blacklisted)
122. Tenant notes (admin-only remarks)

## 2.4 Rent Invoicing (123–135)
123. Monthly rent due auto-generation (on configured due date, per tenant)
124. Rent due includes: base rent + utility share + meal plan + late fee (if any) − adjustments
125. Pro-rata rent calculation (for mid-month joiners / leavers)
126. Rent due list (all tenants, this month, paid vs unpaid)
127. Due date configuration (e.g. 5th of each month, per location)
128. Late fee rule setup (₹X per day after due date, or flat ₹Y)
129. Auto late-fee application
130. Rent waiver / discount (with reason, audit-logged)
131. Rent revision (rent increase, effective from a date, history retained)
132. Rent receipt text generation (tenant name, room, month, amount, mode, receipt no.)
133. Revenue stamp flag on cash receipts > ₹5,000 (as per Indian Stamp Act)
134. Receipt numbering (sequential per location per FY)
135. Receipt share via WhatsApp (one tap — opens wa.me with receipt text)

## 2.5 Rent Collection & Payment Recording (136–145)
136. Payment entry by admin (tenant, amount, date, mode: UPI / Cash / Bank transfer)
137. Partial payment support (part paid, balance carried forward)
138. Advance payment support (tenant pays 2 months in advance)
139. Payment allocation (apply payment to oldest due first)
140. Outstanding balance per tenant (running ledger)
141. UPI QR display (per-location QR shown on screen for tenant to scan — 0% MDR)
142. Payment confirmation (admin marks confirmed after bank/UPI check)
143. Payment reversal (if bounced/reversed — audit-logged)
144. Daily collection summary (how much collected today, by whom, which mode)
145. Cash collection reconciliation (rent cash collected vs deposited to bank)

## 2.6 Rent Reminders (146–152)
146. Reminder list generation (all tenants with dues, sorted by days overdue)
147. WhatsApp reminder via wa.me deep link (pre-filled: tenant name, amount, due date, UPI ID)
148. One-tap send per tenant from the reminder list
149. Reminder schedule: T-3 (before due), T-0 (due date), T+3, T+7, T+15
150. Reminder log (which reminder sent, when, by whom)
151. Escalation flag (tenant overdue > 15 days → highlighted red on dashboard)
152. Bulk reminder mode (go down the list, tap-send each — fast for 200 tenants)

## 2.7 Security Deposits (153–160)
153. Deposit amount per tenant
154. Deposit received entry (date, amount, mode, receipt)
155. Deposit ledger (running balance per tenant)
156. Deposit deduction entry at move-out (damages, dues, cleaning)
157. Deduction line items with description + amount
158. Refund calculation (deposit − deductions − outstanding rent)
159. Refund payment entry (date, mode)
160. Deposit liability report (total deposits held across all hostels)

## 2.8 Utility Bill Splitting (161–167)
161. Utility bill entry (type: electricity / water / gas, location, period, total amount)
162. Meter reading entry (previous, current, units consumed)
163. Split method selection: equally per bed / by occupancy-days / by room / fixed per bed
164. Auto-calculation of per-tenant utility share
165. Utility share auto-added to next rent invoice
166. Utility cost report (per location, per month, trend)
167. Utility payment tracking per location

## 2.9 Move-Out / Vacating (168–176)
168. Notice entry (tenant gives notice — record notice date)
169. Auto-calculate vacate date (notice date + notice period)
170. Vacating list (upcoming vacancies — for planning new admissions)
171. Move-out inspection notes (admin records observations)
172. Final settlement sheet (pending rent + damages − deposit = payable/refundable)
173. Settlement approval (Super Admin)
174. Bed auto-freed on move-out completion; tenant status → vacated
175. Move-out date recording
176. Historical move-out records

## 2.10 Meal Plans / Mess (177–185)
177. Meal plan definitions (Breakfast only / Lunch only / Full board, with monthly price)
178. Tenant subscription to a meal plan (start date, end date)
179. Meal charge auto-added to rent invoice
180. Daily headcount report (how many tenants for breakfast/lunch/dinner tomorrow)
181. Headcount feeds restaurant shift planning + consumption estimation
182. Tenant meal skip entry (admin records if tenant informs they'll skip)
183. Mess cost tracking (stock transferred from restaurant → hostel mess, valued in ₹)
184. Mess profitability (meal plan revenue − mess consumption cost)
185. Meal plan cancellation + pro-rata refund calculation

## 2.11 Hostel Reports (186–194)
186. Occupancy report (occupancy % per location, per month, trend)
187. Rent collection report (invoiced vs collected, collection efficiency %)
188. Outstanding / defaulters report (tenants with dues, aged 0–30 / 30–60 / 60+ days)
189. Tenant movement report (joined / vacated / transferred this month)
190. Revenue report per location (rent + meals + utilities)
191. Deposit report (held, refunded, deducted)
192. Utility cost per bed report
193. Vacancy forecast (upcoming vacancies from notices)
194. Export all reports (CSV / PDF)

---

# MODULE 3: EMPLOYEE MANAGEMENT (195–241)

## 3.1 Staff Records (195–206)
195. Employee registration (name, phone, DOB, gender)
196. Address (present, permanent)
197. Emergency contact
198. Joining date
199. Role / designation (cook, helper, cleaner, watchman, hostel warden, manager)
200. Assigned location(s) — can be assigned to restaurant and/or hostels
201. Monthly salary amount (flat figure — no complex salary structure)
202. Bank account / UPI ID (for owner's reference when paying manually)
203. Employment status (active / on leave / left)
204. Exit date + exit reason (if left)
205. Staff notes (admin remarks)
206. Contact information and reference details

## 3.2 Shift Rota / Duty Roster (207–217)
207. Duty roster creation (week view: employee × day)
208. Assign employee to location + shift (Breakfast / Lunch / Dinner / Full day / Night)
209. Cross-location assignment (same employee: restaurant Mon, Hostel-B Tue)
210. Conflict detection (same employee, overlapping shifts, same time)
211. Copy previous week's roster (one tap, then adjust)
212. Roster templates (standard weekly pattern)
213. Open shift highlighting (unassigned shift → red)
214. Roster publish + WhatsApp share (send roster image/text to staff group)
215. Roster change log (who changed what)
216. "Who's on duty now" live board (across all locations)
217. Roster print/export (PDF for noticeboard)

## 3.3 Attendance (218–227)
218. Daily attendance marking by admin (Present / Absent / Half-day / Leave / Week-off)
219. Bulk attendance marking (mark all present, then change exceptions — fast)
220. Attendance per location (admin marks only their location's staff)
221. Late arrival flag + late minutes
222. Overtime hours entry
223. Attendance calendar view per employee (month grid)
224. Attendance edit (audit-logged; locked after payroll run)
225. Monthly attendance summary (present days, absent days, leaves, OT hours)
226. Attendance % per employee
227. Low-attendance alert (employee below X% attendance)

## 3.4 Leave Management (228–234)
228. Leave types (Casual, Sick, Unpaid, Week-off)
229. Leave allocation per employee per year
230. Leave entry by admin (employee informed, admin records)
231. Leave approval (Super Admin / Admin approves)
232. Leave balance tracking (used vs remaining)
233. Leave calendar (who's on leave when — helps rota planning)
234. Unpaid leave auto-flagged for salary deduction

## 3.5 Salary Advances (235–242)
235. Advance request entry (employee asked, admin records: amount, date, reason)
236. Advance approval workflow (Super Admin approves)
237. Advance paid entry (date, mode)
238. Advance ledger per employee (running outstanding balance)
239. Auto-deduction from next payroll
240. Partial deduction option (deduct in instalments over N months)
241. Advance history per employee
242. Total advances outstanding report (how much money is out with staff)

## 3.6 Payroll (243–252)
243. Monthly payroll run (per location or all locations)
244. Payroll calculation: monthly salary − unpaid-leave deduction − advance deduction + OT + bonus
245. Per-day salary calculation (monthly salary ÷ working days)
246. Bonus / incentive entry (festival bonus, performance bonus)
247. Payroll preview (see all employees, all amounts, before finalising)
248. Payroll approval by Super Admin
249. Payslip PDF generation per employee
250. Payslip WhatsApp share (one tap per employee)
251. Payroll lock after approval (edits require Super Admin + audit log)
252. Payment marked as paid (owner pays offline via bank/UPI/cash, then marks it done here)

## 3.7 Staff Reports (253–259)
253. Salary cost report (total payroll per month, per location)
254. Attendance report (period-wise, per employee)
255. Advance outstanding report
256. Staff cost allocation (how much staff cost belongs to restaurant vs each hostel)
257. Overtime report
258. Staff turnover report (joined / left)
259. Export all reports (CSV / PDF)

---

# MODULE 4: OWNER DASHBOARD & CROSS-CUTTING (260–316)

## 4.1 Authentication & Roles (260–269)
260. Super Admin (Owner) login — full access to everything
261. Admin (Manager) login — restricted to assigned location(s)
262. Login via email/phone + password
263. Session management + auto-logout on inactivity
264. Password reset flow
265. Create / edit / deactivate Admin accounts (Super Admin only)
266. Assign locations to an Admin
267. Permission matrix (what an Admin can and cannot do — e.g. cannot approve payroll, cannot delete records)
268. Login audit log (who logged in, when, device/IP)
269. Optional 2FA for Super Admin

## 4.2 Owner Dashboard (270–285)
270. Today's snapshot card: restaurant income (all shifts), expense, net
271. Shift status card (Breakfast ✓ closed, Lunch ✓ closed, Dinner ⏳ open)
272. Occupancy card (beds occupied / total, % across all hostels)
273. Rent collection card (collected this month vs due, %)
274. Overdue rent card (count of defaulters + total ₹ outstanding)
275. Low stock card (items below reorder level, count + list)
276. Stock value card (current stock worth in ₹)
277. Staff on duty card (who's on duty right now, per location)
278. Pending payables card (supplier credit not yet settled)
279. Advances outstanding card (money out with staff)
280. Cash position card (expected cash in hand across locations)
281. Alerts feed (variance mismatches, expiry warnings, price-rise alerts)
282. Location filter (view all, or drill into one hostel / restaurant)
283. Date range picker
284. Trend charts (income/expense last 30 days, occupancy last 12 months)
285. Mobile-optimised dashboard (owner checks on phone)

## 4.3 Unified Analytics (286–296)
286. Consolidated income (restaurant + rent + meals + utilities)
287. Consolidated expense (purchases + salary + utilities + misc)
288. Net position per month (income − expense) — management view, not accounting
289. Business comparison (restaurant vs hostels — which earns more, costs more)
290. Location comparison (Hostel A vs B vs C: occupancy, collection %, cost)
291. Per-shift profitability (Breakfast vs Lunch vs Dinner)
292. Cost per bed (total hostel cost ÷ occupied beds)
293. Food cost % (raw material consumed ÷ restaurant income)
294. Month-on-month and year-over-year comparison
295. Custom period reports
296. Export everything (CSV / Excel / PDF)

## 4.4 Notifications & Alerts (297–303)
297. WhatsApp alert to owner: shift closed with variance
298. WhatsApp alert: low stock / reorder needed
299. WhatsApp alert: rent overdue > 15 days
300. WhatsApp alert: daily summary at day end (income, expense, occupancy)
301. In-app notification centre
302. Alert configuration (owner chooses which alerts to receive)
303. Alert log (what was sent, when)

## 4.5 Language, Mobile & UX (304–310)
304. Tamil + English interface toggle
305. Bilingual PDFs (receipts, payslips, reports)
306. Progressive Web App (installable on Android phone)
307. Mobile-first design (all data entry works one-handed on a phone)
308. Offline-tolerant data entry (shift entry / stock entry queued if no internet, syncs later)
309. Fast entry UX (numeric keypads, recent-items shortcuts, minimal taps)
310. Dark mode (optional)

## 4.6 Data, Compliance & Audit (311–320)
311. Audit log on all money and stock records (who / what / before / after / when)
312. Immutable audit trail (insert-only, never editable)
313. Sensitive-action log (rent waiver, stock adjustment, payroll edit, shift reopen)
314. DPDP consent tracking for tenant KYC data
315. Masked Aadhaar storage (last 4 digits only)
316. Data export per tenant/employee (on request)
317. Data deletion / archival after tenant vacates + retention period
318. Nightly automated backup to Cloudflare R2
319. Monthly backup restore test
320. Data export (full CSV dump of all tables)

## 4.7 System Settings — Super Admin only (321–329)
321. Organisation profile (name, logo, contact)
322. Location management (add/edit hostels, restaurant)
323. Shift definitions (names, timings)
324. Expense categories (add/edit)
325. Stock categories & units (add/edit)
326. Rent due date, late-fee rules, notice period defaults
327. UPI IDs per location (for QR display)
328. Reorder-level defaults
329. Receipt numbering series configuration

---

# MODULE 5: PRODUCTION-GRADE ENGINEERING (330–359)

## 5.1 Testing (330–336)
330. Unit tests: all money math (rent pro-rata, late fee, payroll, deposit settlement, stock valuation)
331. Unit tests: stock math (opening + in − out − waste = closing)
332. RLS policy tests (pgTAP — Admin of Hostel A can never read Hostel B data)
333. E2E tests: shift close flow, rent payment flow, payroll run
334. CI pipeline: type-check + lint + tests must pass before merge
335. Migration testing on staging before production
336. Monthly backup restore test (automated)

## 5.2 Security (337–346)
337. Row-Level Security on every table (enabled in same migration as table creation)
338. Zod validation on every server action
339. Authorization check in every server action (verify role + location scope)
340. Rate limiting on login + mutation endpoints
341. Secrets only in server env vars (never in client bundle)
342. Security headers (CSP, HSTS)
343. Failed-login lockout
344. Supabase Security Advisor run before every release
345. No service_role key in client code — ever
346. No photo uploads — simplifies security significantly

## 5.3 Data Integrity (347–354)
347. DB transactions wrapping multi-table writes (shift close, payroll, stock adjustment)
348. Idempotency keys on offline-synced entries (no duplicate shift entries)
349. Foreign key constraints everywhere
350. CHECK constraints (amounts ≥ 0, stock qty ≥ 0)
351. UNIQUE constraints (receipt numbers, one shift entry per shift per day per location)
352. Postgres triggers writing audit logs automatically
353. Negative-stock guard at DB level
354. Monthly integrity check job (orphan records, sequence gaps, stock reconciliation)

## 5.4 Reliability & Monitoring (355–359)
355. Error monitoring (Sentry free tier, with rate limiting)
356. Uptime monitoring (UptimeRobot on the app)
357. Free-tier usage monitoring (DB size, storage, egress — alert before hitting limits)
358. Monthly data archival (old shift entries, audit logs → Cloudflare R2)
359. One-page incident runbook (restore backup, resume paused DB, rotate keys)

---

# SUMMARY

**Total: 359 features** (down from 375 due to removal of all photo uploads)

| Module | Features | Notes |
|---|---|---|
| 1. Restaurant — Stock & Shift Ledger | 92 | POS/menu/KDS/billing removed; stock management heavily expanded; no photos |
| 2. Hostel | 102 | Core tenancy + rent + deposits + meals retained; no KYC images |
| 3. Employee | 59 | Admin-entered records retained; no photos |
| 4. Owner Dashboard & Cross-cutting | 70 | Focused on 2-role model |
| 5. Production Engineering | 30 | Unchanged — still production-grade |

**Key improvements from removing photos:**
- No Supabase Storage quota concerns (1 GB sits mostly unused)
- DPDP compliance is simpler (no sensitive documents to manage)
- Smaller database (text only, no blobs)
- No file-upload error handling
- Faster queries (no image URLs to serialize)
- Security is tighter (no public URLs, no signed-URL expiry to manage)

**Aadhaar storage (hard rule):** store only `aadhaar_last4` (e.g. "1234") in text. Full number never touches the app.
