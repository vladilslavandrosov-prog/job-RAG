# Project conventions

## Инструкции — всегда в HTML

Для любых инструкций (пошаговых how-to документов для клиента или для внутреннего использования) стандартный формат — самодостаточный HTML-файл, а не только `.md`/`.docx`.

- Используй визуальную систему (палитра, типографика, компоненты — nav-rail, callout, qa-card, ol.steps и т.д.) из уже существующих примеров:
  - [`docs/platform/instrukciya-novye-atributy-maskirovaniya-otchet-brokera.md`](docs/platform/instrukciya-novye-atributy-maskirovaniya-otchet-brokera.md) → HTML-версия в артефактах этой сессии
  - [`docs/platform/instrukciya-rabota-s-rag-standalone.html`](docs/platform/instrukciya-rabota-s-rag-standalone.html) — канонический образец разметки/стилей, копировать CSS-токены и структуру секций отсюда
- Публиковать как Artifact (см. `artifact-design` skill перед первой публикацией) и сохранять копию файла в `docs/platform/*-standalone.html`.
- `.md`-версия в `docs/platform/` остаётся как более полная внутренняя справка (может включать разделы, которых нет в клиентской HTML-версии); `.docx`-версия в `docs/analysis/` — для печати/пересылки, тем же содержанием, что и HTML.
- Держать все версии (HTML/.md/.docx) в синхронизированном состоянии при правках — правки вносить во все три сразу.
