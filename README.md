# job-RAG

Документация и разбор кейсов по корпоративной RAG-системе для брокера/инвестиционного советника.

## Структура

- `docs/sources/` — исходные материалы (ТЗ, логи диалогов с системой).
- `docs/analysis/` — разбор кейсов: соответствие ТЗ, найденные дефекты, архитектурные предложения.
- `docs/glossary/` — глоссарий: базовые понятия RAG-систем простыми словами, с привязкой к проекту.
- `docs/platform/` — база знаний по интерфейсу платформы «Синапс.Инсайт»: разбор экранов по скриншотам.
- `docs/demo-retail/` — демо-кейсы для ретейла: сценарии использования платформы и (на втором этапе) пакет документов под них.
- `docs/sales-enablement/` — разбор внутреннего материала по методике продаж платформы (лендинг для сейлз-менеджеров): аргументы питча, кейсы клиентов, инструкции по демо, разбор возражений.

## Кейсы

- [`docs/analysis/case-01-d8-014-brief.md`](docs/analysis/case-01-d8-014-brief.md) — приёмочный разбор диалога подготовки брифа к встрече с клиентом D8-014.
- [`docs/analysis/case-02-tz-deep-analysis-and-proposals.md`](docs/analysis/case-02-tz-deep-analysis-and-proposals.md) — глубокий анализ ТЗ (противоречия, пробелы), предложения по архитектуре и новые кейсы использования агента.
- [`docs/analysis/case-03-pilot-tz-ai-guard.md`](docs/analysis/case-03-pilot-tz-ai-guard.md) — новое ТЗ оплачиваемого пилота с компонентом AI Guard: скоуп работ, тестовые сценарии и критерии приёмки; закрывает давний открытый вопрос про периметр данных и модель `OpenAI/gpt-5.4 · veai`.
- [`docs/analysis/case-04-sales-pitch-critique.md`](docs/analysis/case-04-sales-pitch-critique.md) — критический разбор презентации «Единый корпоративный ИИ-слой» для команды продаж: где заявленное не совпадает с реально задокументированным поведением платформы, готовые ответы на возражения покупателя.

## Глоссарий

- [`docs/glossary/README.md`](docs/glossary/README.md) — оглавление всех терминов.

## Платформа «Синапс.Инсайт»

- [`docs/platform/README.md`](docs/platform/README.md) — оглавление разделов платформы, разобранных по скриншотам.
- [`docs/platform/html/user-guide.html`](docs/platform/html/user-guide.html) и [`docs/platform/html/admin-guide.html`](docs/platform/html/admin-guide.html) — руководство пользователя и руководство администратора отдельными HTML-страницами, по ролям, а не по экранам меню.

## Демо-кейсы для ретейла

- [`docs/demo-retail/scenarios.md`](docs/demo-retail/scenarios.md) — этап 1: 8 сценариев использования платформы на материале ретейла, каждый нацелен на конкретную возможность платформы.
- [`docs/demo-retail/dataset/README.md`](docs/demo-retail/dataset/README.md) — этап 2: готовый пакет из 15 документов (Word/Excel) для загрузки в платформу и полный сценарий live-демо с ожидаемыми ответами.
- [`docs/demo-retail/presentation/README.md`](docs/demo-retail/presentation/README.md) — презентация (pptx) и сопроводительный документ (docx) с вопросами и ответами по всем 8 сценариям.
- [`docs/demo-retail/admin-setup/README.md`](docs/demo-retail/admin-setup/README.md) — внутренняя инструкция администратора: загрузка документов и настройка «Графа доступа» на примере Сценария 2.

## Методика продаж

- [`docs/sales-enablement/README.md`](docs/sales-enablement/README.md) — разбор загруженного лендинга для сейлз-менеджеров: структура питча, кейсы клиентов, инструкции по подготовке демо, разбор возражений; новые факты про партнёра «Veai» и уточнение комплаенс-вопроса про периметр данных.
- [`docs/sales-enablement/slide-breakdown.md`](docs/sales-enablement/slide-breakdown.md) — постраничный разбор презентации «Единый корпоративный ИИ-слой»: суть, акценты, примеры-реплики и два варианта объяснения каждого слайда клиенту («просто» / «очень просто»).
- [`docs/sales-enablement/client-qa-prep.md`](docs/sales-enablement/client-qa-prep.md) — лист для команды продаж с ожидаемыми вопросами клиента и готовыми ответами (не часть презентации).
- [`docs/sales-enablement/slide-breakdown.html`](docs/sales-enablement/slide-breakdown.html) — оба материала выше объединены в одну HTML-страницу.
