# Engineering Journal — paved-road-ai-eks

A running log of issues encountered, debugging steps taken, and lessons learned while building the reference architecture. Written for two audiences: my future self (so I don't repeat mistakes) and interviewers (so they can see how I think through problems).

**How to use this journal:**
- Log every non-trivial error you hit — even small ones
- Follow the same template for each entry (context → symptom → hypothesis → fix → lesson)
- Never edit past entries to look smarter after the fact — the messy debugging is the point
- Reference this file from the main README under "What I learned building this"

**Entry format:**

Each entry has 6 sections. Keep them short — 2-3 sentences each is usually enough.

```
## YYYY-MM-DD — Short title
**Context:** What were you trying to do?
**Symptom:** What went wrong (exact error message if possible)?
**Hypothesis:** What did you think was wrong initially?
**Root cause:** What was actually wrong?
**Fix:** What resolved it (exact commands or config change)?
**Lesson:** What will you do differently next time?
```

---

## 2026-08-24 — HuggingFace token validation returns misleading auth error

**Context:** Setting up HuggingFace authentication for Week 4 — needed to verify the token could download Mistral 7B model weights before deploying the InferenceService. Ran the standard `curl /api/whoami` test that most tutorials suggest.

**Symptom:** `{"error":"Invalid username or password."}` returned for every token attempt, even freshly generated tokens with correct Read permissions. Same error returned when the endpoint was called with no authorization header at all — a hint that the endpoint itself might be the problem, not the credential.

**Hypothesis:** Initial guesses (all wrong):
1. Token was truncated during copy-paste
2. Token had insufficient scoping (fine-grained token issue)
3. Model access hadn't been granted yet

Spent ~30 minutes revoking and regenerating tokens before running a proper diagnostic — testing the endpoint with no auth at all. Same error appeared, which proved the endpoint wasn't validating credentials properly for either case.

**Root cause:** The `/api/whoami` endpoint is deprecated on HuggingFace and returns the same generic "Invalid username or password" message regardless of what token you send it. It's misleading — the error suggests a credential problem when it's actually an endpoint problem.

**Fix:** Switched to testing against the actual resource endpoint that KServe uses in production:

```bash
curl -sL -o /dev/null -w "HTTP status: %{http_code}\n" \
  https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3/resolve/main/config.json \
  -H "Authorization: Bearer $HF_TOKEN"
```

Also verified with the current API endpoint: `/api/whoami-v2` (note the `-v2` suffix). Both returned HTTP 200 with correct JSON response — confirming the token was valid all along.

**Lesson:** Generic error messages hide real failures. When debugging authentication issues, test against the exact endpoint your production code will hit — not against generic "check my credentials" endpoints. Those endpoints often lag behind API changes and give false negatives. Also: when a fresh token fails the same way as an old token, stop regenerating credentials and check whether the endpoint itself has changed.

---

## Template for future entries

Copy this block for each new issue.

```
## YYYY-MM-DD — [Short title]

**Context:** [What were you doing? What phase of the project?]

**Symptom:** [Exact error message. Copy-paste it. Include the command that produced it.]

**Hypothesis:** [What did you think was wrong initially? Include your first attempts even if they were wrong — the wrong hypotheses are useful debugging material.]

**Root cause:** [What was actually wrong. Be specific — not "network issue" but "kube-proxy pod on node ip-10-0-1-x had OOMKilled state due to insufficient memory request."]

**Fix:** [Exact commands, config changes, or PRs that resolved it. Someone reading this in 3 months should be able to reproduce the fix.]

**Lesson:** [What will you do differently? What signal will you look for earlier next time?]
```

---

## Categories to log — don't skip these

Every project has predictable categories of pain. Log every instance:

- **Authentication & tokens** — HF, AWS IAM, ArgoCD, Kubernetes ServiceAccounts
- **Networking** — VPC CIDR issues, security groups, IPv6, kube-proxy
- **Karpenter provisioning** — instance type not available, spot interruption handling, taints/tolerations mismatch
- **GPU workloads** — CUDA errors, driver mismatches, OOMKilled with GPU pods, model loading timeouts
- **KServe / vLLM** — model download failures, InferenceService stuck in unknown state, autoscaling misbehavior
- **ArgoCD sync issues** — OutOfSync loops, resource conflicts, RBAC on Applications
- **Terraform state** — provider version conflicts, moved/removed blocks, drift detection
- **Cost surprises** — unexpected NAT charges, GPU node forgotten running, data transfer between AZs
- **Helm chart quirks** — CRD ordering, values structure changes between versions
- **Observability gaps** — ServiceMonitor not scraped, dashboards showing gaps, alerts not firing

---

## Interview-worthy stories to develop

As you accumulate entries, some will be interview-worthy — the ones with genuine surprise, non-obvious root cause, and a lesson that transfers to any senior role.

Mark those with `⭐ INTERVIEW` at the top and revisit them before technical rounds. Common patterns interviewers ask about:

- "Walk me through your most memorable debugging session"
- "Tell me about a time a fresh-looking setup broke unexpectedly"
- "Describe a time when the error message misled you"
- "What's an operational lesson you learned the hard way?"

The HF token entry above already fits the "misleading error message" pattern — that's a 5-minute story with a clear lesson. Rehearse it out loud once, and it becomes an easy answer for interview rounds.

---

## Notes for the README

Once this journal has 8–10 entries, extract the top 3 into the main README's "What I learned building this" section — but keep them short and punchy there. The full detail lives here in the journal.

Example README bullet from the HF entry above:
> **HuggingFace `/api/whoami` returns misleading auth errors** — the endpoint is deprecated but still exists. Test against the actual resource endpoint your code will use, not against generic auth check endpoints.

That single line, expanded from the full journal entry, tells a hiring manager everything they need to know about your engineering discipline.
