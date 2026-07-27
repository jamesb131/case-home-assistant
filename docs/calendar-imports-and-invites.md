# Calendar Imports And Invite Capture

## School Calendar Feeds

CASE can ingest public `.ics` feeds into its local calendar store. School feeds are treated as an inbox: imported events are hidden from the main calendar until approved.

In the CASE Core add-on settings, use:

```text
school_calendar_feeds: "St Francis Butler|https://calendar.google.com/calendar/ical/brightoncps.wa.edu.au_pq6tviier5bfodispuek6br16c%40group.calendar.google.com/public/basic.ics"
```

The optional third field assigns the default child/audience:

```text
school_calendar_feeds: "St Francis Butler|https://calendar.google.com/calendar/ical/brightoncps.wa.edu.au_pq6tviier5bfodispuek6br16c%40group.calendar.google.com/public/basic.ics|Leo"
```

Multiple feeds can be comma-separated:

```text
school_calendar_feeds: "St Francis Butler|https://example.com/calendar.ics|Leo,Other Calendar|https://example.com/other.ics|Benny"
```

Imported events are stored locally. Obvious non-matches, such as Year 3-6, Kindy, Pre-Primary, REA, Confirmation, and Year 1 liturgy events while Leo is in Year 2, are marked ignored. General school/community events are approved by default. Pending school events appear in Planner under School review, where they can be kept or ignored. Removing an imported event in CASE hides it from CASE without changing the upstream school calendar.

## Kids Party Invite Prompt

Use this prompt with a photo or forwarded invite text, then paste the result into CASE chat.

```text
Extract this kids party invite into one CASE command.

Return only a short command I can paste into CASE.

Include:
- child/person if clear
- party child or event title
- date
- start time and end time if shown
- location/address
- RSVP or notes if useful
- optional task to buy a present, due a few days before the party

Format:
Add event <title> <date> <start time> till <end time> at <location>. Also add task buy present for <party child> due <date>.

If any key detail is missing, ask one concise question instead.
```

Example output:

```text
Add event Leo birthday party August 15 2pm till 4pm at Crocs Butler. Also add task buy present for Leo birthday party due August 12.
```
