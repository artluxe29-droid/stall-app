# Opening Stall to everyone

Status: **Waiting for approval** (written 17 Oct 2026).

## The decision

Stall stops being students-only. Anyone in Nigeria can buy and sell. Students stay at the heart of it: their campus is still their home feed, and they get a Student badge and campus perks. When they graduate, their store, ratings and badges go with them.

**Positioning:** *Born on campus. Open to everyone.* Stall is where young Nigerians buy and sell safely, and it starts with students.

**The matric number is removed completely.** Formats differ by school, it can't be checked reliably, and it creates review work. Escrow already protects buyers' money. For sellers, what matters is that the money goes to a real, named person, and the bank account name check already proves that.

## What changes for people

| | Today | After |
|---|---|---|
| **Who can join** | Students (and approved campus vendors) | Anyone |
| **Sign-up** | School, name, matric, email, WhatsApp, password, hostel | Name, WhatsApp, email, password, **state and area**. Optional: "I'm a student", then pick a school |
| **Sign in** | Matric number or phone | Phone number (old matric sign-ins keep working quietly so nobody is locked out) |
| **Forgot password** | Matric or phone | Phone |
| **To buy** | Students must be verified first (gate on by default) | Nothing extra: Stall holds the money until they have the item |
| **To sell** | Verified student + seller rules | Seller rules + payout account whose name Paystack confirms (already built) |
| **Student badge** | Required | Optional: school email or a school document. It unlocks campus perks |
| **Campus vendors** | Need an invite code or the team's approval | A **business account**, open to any business, with no approval queue. Invite codes still give Founding Seller perks |
| **Feeds** | My school, my state, Nigeria | **My campus** (students), **my area**, my state, Nigeria |
| **Graduates** | Stuck on their school | Untick "I'm a student" or change school. They keep their store, ratings and badges, plus a "Started on campus" badge |

## What stays student-only (the campus identity)

- The **My campus** feed and campus search.
- The **Student badge** on listings and stores.
- **Class collections**, for class reps.
- **Campus partners** (student unions and associations), their codes and banners.
- **Founding Seller** numbers per school.
- **"Students can't sell here"** per school, for schools whose rules forbid it. It hides those students' items from that campus only.

## What gets retired

- **The matric number:** taken off every form, the matric claim flow, the Admin screens and the ID check. **Recommended:** delete the matric numbers already stored, so Stall keeps no data it doesn't need (good practice under Nigeria's data protection law).
- **The "verify first" gate:** off by default. The Admin switch stays in case you ever need it.
- **The vendor approval queue:** business accounts are active straight away.
- **School launch states** (Coming soon / Sellers only / Live) and the **school waitlist**. With Stall open to everyone, a student at a school that isn't "open" yet would be blocked while their neighbour isn't. Whole-Stall controls stay: Close the app, and the short break message. The waitlist data is kept for your records.

## Location: state and area

Everyone picks their **state** and **area**. The area is their Local Government Area, chosen from a list (Nigeria's 774 LGAs, from an official source), never free text. Free text would turn into "Ibadan", "ibadan city", "Bodija, Ibadan"…

- Listings and stores carry the seller's state and area, so "my area" feeds and search work.
- Stores can still pay for state-wide or nationwide reach, as today.
- Students also pick their school. Their campus feed works exactly as now.

## Existing accounts

- **Students:** keep their school and badge. Their state comes from their school. Next time they open Stall, they're asked once: *"Which area are you in?"*
- **Campus vendors:** become business accounts.
- **Listings and stores:** take their owner's state now; the area fills in when the owner answers.
- Nobody has to sign up again.

## Words that change

- **Terms, Rules and Privacy:** for everyone, not just students. Remove matric numbers; add state and area; keep the school-rules line for students who sell on campus.
- **Website:** the hero, "who it's for" and FAQs. The sign-up form changes too.
- **Emails and push messages** that say "students".
- **Play Store listing**, when we get there.

## Order of work

| Step | What | Where | Time |
|---|---|---|---|
| **1. Matric out, doors open** | Remove the matric number everywhere; sign-up without it; phone-only sign-in and reset; gate and "verified to sell" default off; vendors become business accounts with no approval; delete stored matric numbers (if you agree) | Server, website, Admin | 2 to 3 days |
| **2. State and area** | LGA list; state and area on sign-up and accounts; "I'm a student" plus an optional school; listings and stores carry area; My campus / My area / My state / Nigeria feeds; the one-time "Which area are you in?" for existing accounts; retire school launch states and the waitlist | Server, website, Admin | 4 to 6 days |
| **3. Words** | Terms, Rules, Privacy, website copy, emails, guide | Website | 1 to 2 days |
| **4. Native app** | Same sign-up, feeds and badges in the app (it already shares the server), then continue Phase 2 (selling) | `mobile/` | 3 to 4 days, then Phase 2 continues |

Each step ships on its own, tested, behind your approval, like everything so far. Stall stays closed to the public until you reopen it, so nothing changes for anyone until then.

## Risks and how we handle them

- **Becoming "another Jiji".** Campus stays the home feed for students, with the Student badge and campus perks. The message is about young sellers, not classifieds.
- **Scams from non-students.** Escrow already stops the common ones: nobody is paid until the buyer has the item. Payout names are checked by Paystack. Strikes and reports apply to everyone.
- **More support work.** Removing the matric checks, the gate and vendor approvals cuts most manual review. What's left is disputes and the occasional bank name to confirm.
- **Payments rules as volume grows.** Paystack may ask for more business documents (you already have CAC registration). Nothing changes for users.

## Decisions for you

1. **Delete the matric numbers already stored?** Recommended: yes.
2. **Remove the vendor approval queue (business accounts open straight away)?** Recommended: yes.
3. **Area = Local Government Area from a list?** Recommended: yes.
4. **Retire school launch states (Coming soon / Sellers only / Live) and the waitlist?** Recommended: yes.
5. **Tagline "Born on campus. Open to everyone."?** Or your own.
