# Optional direct-address mentions in Slack

In Settings → Privacy & context, enable **Include visible text as context**, then **Mention people addressed by name in Slack**. AI post-processing must also be enabled. The new preference is off by default and does not change the existing explicitly spoken `at Name` option.

The option adds an `@` prefix to a visible name at the start of a sentence when a direct request or thanks-for phrase follows. The name must have a comma after it or follow a greeting. Ambiguous phrases such as `Will you review this?` stay unchanged. For example, `Yuki, can you review this?` becomes `@Yuki, can you review this?`. A full visible display name can support a spoken first name without adding an unspoken surname. `I spoke to Yuki` and `Yuki will review the draft` stay unchanged. Quoted text and existing mentions stay unchanged.

Formatting runs locally after an accepted AI cleanup result, for both Local and cloud providers. It applies only to the Slack desktop bundle and requires current visible-text consent and the current option value. It makes no extra network requests, reads no extra screen data, and needs no conversation-title setting. Failed or rejected AI cleanup retains the original text.

This initial implementation recognizes a bounded set of direct-address phrases. It does not convert every occurrence of a person's name, resolve ambiguous Slack display names to user IDs, or promise a Slack notification. Kol inserts text; Slack determines whether pasted `@Name` text becomes a resolved mention.
