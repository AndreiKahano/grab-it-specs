# Business Logic

> Development of a Web-based community giveaway platform using Next.js and Supabase for students and local residents

- Allowed Platforms: Web, Android

## Project Details

- Company/Startup/Team Name: localgrabs
- Project Code Name: grab-it
- Project Short Code: grabit
- Short Description: A community platform where people post free items for pickup and discover what is available nearby.
- Long Description: grab-it lets people give away items they no longer need, such as books, clothes, school supplies, furniture, and surplus food, and lets nearby students and residents find and claim them. All listings are created by users, pinned to an approximate pickup area, and expire automatically. The platform offers no credits, money, or convertible rewards. Rules are enforced through community-guideline hits and moderator action, not visible reputation. It stores minimal data, keeps no per-user activity trails, and earns revenue mainly from local sponsorship slots. Data resale is the last option and only with consent.

## User Levels

> Note: Modify/rename the list of users based on the actual users that you expect to use the system.

| User Level              | Description |
| ----------------------- | ----------- |
| A. System Administrator | Maintains/overrides system/server configurations, runs data-retention purge jobs, and performs regular backups. |
| B. Administrator        | Manages the general settings of the system (categories, guidelines, retention limits) and generates periodic aggregated analytics and reports. |
| C. Moderator            | Reviews reported listings, removes content that violates community guidelines, and applies guideline hits. |
| D. Contributor          | Logged-in users who post free items, claim items from others, mark items as given, and report violations. |
| E. Guest                | Users who do not log in, but view limited contents on the app/web (nearby listings with approximate locations only). |

## System Requirements

1. The app shall allow the users to authenticate using Google Sign-In integration.
2. The app shall allow the users to post a free item with a photo, title, category, description, approximate pickup area, and expiry time.
3. The app shall allow the users to browse, search, and filter nearby items in list and map views using blurred locations.
4. The app shall allow the users to claim an item, with the giver confirming the claim before the exact pickup location is revealed.
5. The app shall allow the users to edit, mark as given, or delete their own listings, and shall automatically expire listings when their time limit ends.
6. The app shall allow the users to report listings that violate community guidelines.
7. The app shall allow moderators and administrators to review reports, remove content, and apply guideline hits, and shall allow users to give or withdraw consent for data use.

## Required Solution Layers

1. Security and privacy by design. Data Privacy Act compliance, location protection, retention limits, no per-user trails, aggregation thresholds, and consent for any data resale.

## MVP Features and Access

> See the User Levels table for reference.

| Feature                                                      | Access      |
| ------------------------------------------------------------ | ----------- |
| 1. Browse and search nearby items (blurred locations)        | A,B,C,D,E   |
| 2. Google Sign-In and consent management                     | A,B,C,D     |
| 3. Post, edit, mark as given, and delete own listings        | A,B,C,D     |
| 4. Claim items, confirm pickup, and report listings          | A,B,C,D     |
| 5. Review reports, remove listings, and apply guideline hits | A,B,C       |
| 6. Aggregated analytics and guideline/retention settings     | A,B         |
| 7. Server configuration, backups, and data purge jobs        | A           |

## Notes
- Listings are time-limited and auto-expire; expired content is purged per the retention limit.
- Exact pickup locations are shared only after the giver confirms a claim.
- No credits, points, money, or convertible rewards; no visible reputation scores.
- Analytics are shown only as aggregates above a minimum threshold; no per-user trails are stored.
- Revenue direction: local sponsorship slots first; data resale is the last option and requires explicit consent.
- The Android client mirrors the web features and uses the same Supabase-backed API.