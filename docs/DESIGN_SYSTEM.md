# Design System (extracted from `design/MediTrack.dc.html`)

Implemented in `client/lib/core/theme/tokens.dart` and `client/lib/core/widgets/mt_widgets.dart`.

## Tokens

| Token | Value | Use |
|---|---|---|
| Font | Figtree 400–800 (bundled `assets/fonts/Figtree.ttf`) | all text |
| `blue` | `#1877F2` (gradient `#3D95FB → #1877F2 → #1463D8`) | primary actions, active nav |
| `ink` / `ink2` / `muted` / `muted2` | `#101B2D` `#2A3B55` `#647A99` `#45608A` | text |
| `border` / `hairline` / `track` | `#E4ECF8` `#EEF3FA` `#EEF3FA` | dividers, bars |
| Page | white → `#F6F9FF` vertical gradient on `#EAF1FB` | background |
| Status: reported | fg `#1462D6` bg `#E4F0FF` | "Reported taken" |
| Status: awaiting | fg `#855000` bg `#FFF1D3` | due |
| Status: not confirmed/alerted | fg `#A3420F` bg `#FDE9DC` | escalated |
| Status: ok / caregiver-confirmed | fg `#0F7457` bg `#EEF9F4` | |
| Danger | `#D9473A`, deep `#B5362A`, bg `#FDE8E6`, border `#F6CFC8` | |
| Radii | card 24, tile 16, control 14–18, pill 999 | |
| Shadow | `0 14 34 rgba(28,84,160,.10)` | cards |
| Min target | 44–48 px (nav items 58, primary buttons 54–58) | |
| Type scale | 32/800 hero, 28/800 title, 22/700 header, 17–19/700 row title, 15–16 body, 13–14 caption | |

Pills (capsule/tablet in blue, pink, white, amber) are drawn in code (`PillIcon`), not images.

## Components (Flutter)

`MtCard`, `Tappable`, `PillIcon`, `StatusPill`, `PrimaryButton` (gradient, 58 px), `OutlineBtn`,
`TextAction`, `SegControl`, `ChipRow`, `ToggleRow`, `BackHeader`, `PageTitle`, `SectionLabel`, `EmptyBox`,
`ErrorBox`, `LabeledField`, `Avatar`, `ScreenScroll`, `PageBackground`, `FloatingNav`, `showMtSheet`
(28 px top radius, grabber), `confirmDialog`, `SyncBanner`, `DoseRow`.

## Screen map

| Design screen | Flutter |
|---|---|
| Home | `features/home/home_screen.dart` |
| Medications | senior: `home/doses_list_screen.dart`; caregiver: `medications/medications_screen.dart` |
| Medication details | `home/dose_detail_screen.dart` |
| Verify dose | `verification/verify_screen.dart` |
| Analytics | `analytics/overview_screen.dart` (caregiver) |
| Notifications & Safety | `notifications/notifications_screen.dart` |
| Caregiver alert | `escalation/alert_screen.dart` (+ list `alerts_screen.dart`) |
| Profile | `profile/profile_screen.dart` |
| Voice / remind-later / form / outcome sheets | `voice_sheet.dart` / buttons on detail / `_MedForm` / `_resolveSheet` |

## Intentional deviations

1. **Wording**: "Taken" → "Reported taken" (self-report), "Verified" removed; unconfirmed ≠ "Missed".
2. **Removed prototype-only parts**: demo clock, demo reset, simulated outcome picker/call, "this is a
   prototype" notes. Verification and calls are real (camera/OCR/barcode, `tel:`).
3. **Role split**: the design mixed senior and caregiver; seniors get 3 tabs (Home, Medicines, Profile) and
   cannot add/edit medicines; caregivers get Overview/Medicines/Alerts/People/Profile; admins get a separate area.
4. **Analytics** is caregiver-only and reports reported / confirmed / not-confirmed / recorded-not-taken
   separately instead of a single adherence %.
5. "Repeats: Every other day" is not supported by the schedule model → replaced by Weekends; any weekday set
   is supported by the API.
6. Threshold "Escalate after 15/30/60" → free numeric T+verify / T+escalate (defaults 5 / 45 from the brief).
7. "Undo confirmation" dropped (append-only history).
8. New screens in the same language: sign-in, household setup, People (seniors, caregivers+permissions,
   alert rules), admin Users/Roles/Audit/System.
9. Added `Larger text` (×1.2) and `Reduce motion` honour system accessibility settings too.
