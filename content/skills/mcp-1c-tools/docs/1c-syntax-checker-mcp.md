# 1c-syntax-checker-mcp — tool catalog

BSL syntax and style validation via BSL Language Server.

> Load this file only if the `1c-syntax-checker-mcp` server is actually available in the current session.

| Tool | Purpose | When to use |
|---|---|---|
| **syntaxcheck** | Check BSL syntax and style via BSL Language Server | After writing code — verify no errors. **Limit: 1 call per cycle by default, up to 3 only if a substantive defect remains** |

## Input format

- `syntaxcheck` принимает **только текст BSL-кода** в параметре запроса. Передача путей к файлам (`.bsl`, `.os` и т.п.) или ссылок на модули в репозитории не поддерживается — такой ввод будет интерпретирован как код и приведёт к ложным синтаксическим ошибкам.
- Перед вызовом прочитайте нужный модуль (или его фрагмент) через `Read` и передайте полученный текст как код. Для крупных модулей допустимо проверять отдельный изменённый фрагмент, обрамлённый минимально необходимым контекстом (объявление процедуры/функции целиком).

## Notes on the limit

- A **cycle** is one logical edit of one module, from the first edit until either a clean `syntaxcheck` is achieved or the limit is exhausted.
- Each new edit of the module starts a new cycle.
- **Default budget** — 1 call per cycle. Run the validator, fix what it found, deliver.
- **Re-run budget** — up to 3 total calls per validator per cycle, but only when the previous run returned a **substantive defect**: logic / metadata / data integrity / security / transaction / lock / performance-critical. Style, naming, formatting, BSLLS noise — do **not** re-run; fix in the edit and move on.
- The same policy applies to `check_1c_code` and `review_1c_code` from `1c-code-check-mcp`.
- Once the limit is hit — fix the substantive errors and move on; style warnings after the limit do not block delivery.
- It only makes sense to re-run `syntaxcheck` after an actual code edit — re-runs without changes are forbidden (see `AGENTS.md → MCP Tool Calling`).
