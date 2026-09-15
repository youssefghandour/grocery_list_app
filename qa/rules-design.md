# Firestore access model used for the repair

The existing app uses Firestore Standard edition. Testing targets only the isolated `demo-na2slna-qa` local emulators. No remote database configuration is changed.

- Users read their own profile and members of their current household. Profile edits cannot change paid flags, membership or authority.
- A new household, default list, invite and the creator's membership are written atomically. The creator can become admin only for that newly created household.
- Joining an existing household is a trusted callable operation. It derives identity from Auth, validates the invitation age and serializes membership-limit checks. Clients cannot write arbitrary membership.
- Leaving and admin removal clear membership; client paid upgrades are denied.
- All members collaborate on lists and items; only the household owner renames the household or refreshes its invite. Item creator and household scope cannot be rewritten.
- Queries in scope: user profile by UID, users where householdId equals current user's household, household by ID, nested lists/items ordered by createdAt, nested checked-item filtering, and items collection group where householdId equals current household with limit50.
- The collection-group allowance grants reads only. Writes remain scoped to the nested household path.
- Private payment orders and transactions have no client allow rules.
- Validators check both creates and updates, allowed keys, types and lengths. Existing legacy item documents without householdId remain editable under their household path, but do not participate in the group query until backfilled.
- Updates can preserve an existing nonblank quantity string of at most 30 characters or an exactly unchanged blank display name of at most 120 characters. Creates stay strict, and changing either field must produce a valid new value. Positive and negative emulator tests cover these bounded legacy exceptions.

Deployment must include the join callable before the tightened rules are activated. The regression suite exercises positive collaboration and creation/leave flows as well as denied access. See the updated assessment/report after tests finish.
