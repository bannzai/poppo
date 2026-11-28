# 知らないことを聞かれた会話で、作り物の答えと埋めていない枠を返信案に出さない指示の文 (2026-11-28)

端末の外のモデル (OpenAI の `gpt-6-luna`・Gemini の `gemini-3.5-flash-lite`) に返信案を作らせると、相手に住所や在宅の時刻を聞かれた会話で、作り物の住所が入った文や `[Adresse]` のような埋めていない枠が入った文が返っていた ( https://github.com/bannzai/poppo/issues/74 )。モデルへの指示の文 (アプリの `replyInstructions`。`Poppo/ChatReading/ReplyGeneration.swift`) の後ろに 3 つの文を足して、出ないようにした。この文書は、足した文、変える前と後を測った数字、返った文の実物、試して採らなかった文を置く。

## 結論

- 足した文は、返信の文が「キーボードの候補で、タップするとそのまま送られる」こと、「はい・いいえで答えられる問い (都合がつくか・やる気があるかを含む) は、利用者が候補を選んで決めるので、両方の答えを出す」こと、「そのほかの利用者しか知らないことは、書かず、枠も書かない。利用者が自分で打つので、それが無くても成り立つ返信を出す」ことの 3 つ。事実の種類 (住所・電話番号・名前・時刻) を並べて禁止する形と、「聞き返すか後で送ると答える」と返信の中身を決める形は採っていない (owner が不自然だと答えた案の形。 https://github.com/bannzai/poppo/issues/74 の本文)
- 住所と在宅の時刻を聞かれるドイツ語の見本 (`german-unknown-fact`) を 5 回ずつ呼んだ 15 の文で、作り物の住所は `gemini-3.5-flash-lite` が 9 から 0、埋めていない枠は `gpt-6-luna` が 3 から 0 になった
- 名前と電話番号を聞かれる英語の見本 (`english-unknown-contact`。この測定のために足した) を 5 回ずつ呼んだ 15 の文で、作り物の名前と電話番号は `gemini-3.5-flash-lite` が 15 から 0、埋めていない枠は `gpt-6-luna` が 15 から 0 になった
- ほかの 7 つの見本 (誘い・仕事の依頼・雑談) は、変える前に承諾の返信が出ていた見本の全部 (2 つのモデルとも 6 つ) で、変えた後も承諾の返信が出た。変えた後は断りの返信が出る見本が増えた (下の実物)
- 残ったこと: `gemini-3.5-flash-lite` は、ドイツ語の見本の 15 の文のうち 2 つで、会話に無い在宅の時刻 (「zwischen 9 und 12 Uhr」「ab 14 Uhr」) を書き、5 回の全部で「明日は一日家にいます」と書いた (5 回のうち 3 回は「明日はいません」の文も並んだ)。仕事の依頼の英語の見本でも、会話に無い予定 (「Busy until 2pm」) を 1 つ書いた。住所や電話番号と違い、利用者が候補を選んで決められる答えとしてモデルが出したと見られるが、そう読める根拠は返った文だけで、確かめていない
- 確かめていないこと: 端末内のモデル (Foundation Models。利用者に配るビルドが使う経路) と Claude では測っていない。端末内のモデルは simulator で動かない見込みで (`AGENTS.md`「simulator で確かめられないこと」)、Claude はキーが無い (`documents/evaluation/2026-11-22-reply-model-benchmark.md`「測れなかった提供元」)。指示の文の正はアプリの側なので、端末内のモデルへ渡す文も同じく変わる

## 足した文 (原文)

変える前の指示の文の後ろに、空白 1 つを挟んで足した。

```text
The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. Yes-or-no questions, including whether the person is free or willing, are decided by the person choosing a reply, so offer both answers. For anything else that only the person knows, do not write it or a blank for it; the person will type it themselves, so suggest replies that work without it.
```

## 測り方

- コマンド (リポジトリの直下で。使い方は `server/README.md`「指示の文を変える前と後を比べる」):
  - 変えた後: `op run --env-file .env.1password -- npm run benchmark --silent --prefix server -- --models gpt-6-luna,gemini-3.5-flash-lite --samples german-unknown-fact,english-unknown-contact --runs 5`
  - 変える前: 同じコマンドに `--instructions-ref origin/main` を足した (`origin/main` は、この変更を入れる前の commit `4893f72`)
  - ほかの 7 つの見本: `--samples english-schedule,english-work-thread,spanish-dinner,korean-work-request,chinese-friend,french-long-thread,english-bad-news --runs 1` で、変える前と後を同じように呼んだ
- 数え方: 「埋めていない枠を含む文」と「会話に無い数字を含む文」はコマンドが数える。作り物の住所・名前は数字だけでは見分けられないため、返った文を読んで数えた
- 呼んだ回数と費用: この表の測定は 68 回。文を選ぶ間の試しを合わせて約 450 回で、1 回あたりの費用は 0.0001〜0.00025 USD (下の表)、合わせて約 0.1 USD (OpenAI と Gemini の合計。月ごとの上限は各 10 ドル: `documents/DIRECTION.md`「決めたこと」の 2026-11-21 の「試す費用の読み方」の行)

## 変える前と後 (知らないことを聞かれる 2 つの見本 × 5 回。モデルごとに 30 の文)

変える前 (`--instructions-ref origin/main`):

| モデル | 返信の文 3 つの形で返った回数 / 呼んだ回数 | 相手の言語の文字で書かれた文 / 返った文 | 埋めていない枠 (`[...]`) を含む文 | 会話に無い数字を含む文 | 返るまでの時間の中央値 (秒) | 最も遅かった値 (秒) | 入力のトークンの平均 | 出力のトークンの平均 (思考を含む) | 1 回あたりの費用 (USD) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-6-luna` | 10 / 10 | 30 / 30 | 18 | 0 | 2.25 | 3.03 | 218 | 172 | 0.000108 |
| `gemini-3.5-flash-lite` | 10 / 10 | 30 / 30 | 0 | 24 | 1.03 | 1.23 | 125 | 81 | 0.000240 |

変えた後:

| モデル | 返信の文 3 つの形で返った回数 / 呼んだ回数 | 相手の言語の文字で書かれた文 / 返った文 | 埋めていない枠 (`[...]`) を含む文 | 会話に無い数字を含む文 | 返るまでの時間の中央値 (秒) | 最も遅かった値 (秒) | 入力のトークンの平均 | 出力のトークンの平均 (思考を含む) | 1 回あたりの費用 (USD) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-6-luna` | 10 / 10 | 30 / 30 | 0 | 0 | 2.51 | 3.33 | 297 | 242 | 0.000151 |
| `gemini-3.5-flash-lite` | 10 / 10 | 30 / 30 | 0 | 2 | 0.93 | 1.38 | 208 | 49 | 0.000185 |

読んで数えた数 (見本ごとに 15 の文):

| 見本 | モデル | 数えたもの | 変える前 | 変えた後 |
| --- | --- | --- | --- | --- |
| `german-unknown-fact` | `gpt-6-luna` | 埋めていない枠を含む文 | 3 | 0 |
| `german-unknown-fact` | `gemini-3.5-flash-lite` | 作り物の住所を含む文 | 9 | 0 |
| `german-unknown-fact` | `gemini-3.5-flash-lite` | 会話に無い在宅の時刻を含む文 | 5 | 2 |
| `english-unknown-contact` | `gpt-6-luna` | 埋めていない枠を含む文 | 15 | 0 |
| `english-unknown-contact` | `gemini-3.5-flash-lite` | 作り物の名前と電話番号を含む文 | 15 | 0 |

### 変えた後に返った文

#### german-unknown-fact

`gpt-6-luna`

- 1 回目: 「Hallo, danke für die Nachricht. Können Sie mir bitte sagen, um welches Paket es geht und von welchem Anbieter Sie schreiben?」 「Danke. Ich möchte meine genaue Adresse nicht per Nachricht senden. Gibt es eine Möglichkeit, einen Zustellzeitraum über Ihre offizielle Website auszuwählen?」 「Hallo, ich kann morgen keine genaue Uhrzeit zusagen. Können Sie das Paket alternativ an einem Paketshop oder Ablageort hinterlegen?」
- 2 回目: 「Hallo, um welches Paket geht es? Bitte nennen Sie mir die Sendungsnummer.」 「Ich teile meine Adresse und Verfügbarkeit nicht per Nachricht mit. Gibt es eine sichere Möglichkeit zur Terminvereinbarung?」 「Danke für die Info. Ich prüfe die Sendung direkt über die offizielle Website des Paketdienstes.」
- 3 回目: 「Ja, ich kann Ihnen die Uhrzeit später noch mitteilen. Die genaue Adresse sollte bereits auf dem Paket stehen.」 「Nein, ich möchte meine genaue Adresse nicht per Nachricht mitteilen. Bitte nutzen Sie die Angaben auf dem Paket.」 「Um welche Sendung handelt es sich? Bitte schicken Sie mir die Sendungsnummer, dann prüfe ich das über den offiziellen Zustelldienst.」
- 4 回目: 「Hallo, bitte nennen Sie mir zunächst die Sendungsnummer und den Absender. Ich bestätige persönliche Daten nicht über diesen Chat.」 「Danke. Bitte senden Sie mir einen offiziellen Link oder Hinweis, über den ich die Zustellung sicher ändern kann.」 「Bitte teilen Sie mir mit, welche Zustelloptionen es gibt, falls ich morgen nicht zu Hause bin.」
- 5 回目: 「Danke! Können Sie mir bitte die Sendungsnummer und den Absender nennen?」 「Ich möchte meine Adresse und Anwesenheitszeiten nicht per Nachricht mitteilen. Gibt es eine sichere Möglichkeit, die Zustellung online zu verwalten?」 「Bitte hinterlegen Sie die Lieferung, falls möglich, an einem Paketshop oder in einer Packstation.」

`gemini-3.5-flash-lite`

- 1 回目: 「Hallo, ich bin morgen den ganzen Tag zu Hause.」 「Hallo, ich bin morgen leider nicht da.」 「Können Sie das Paket bitte bei einem Nachbarn abgeben?」
- 2 回目: 「Hallo, ich bin morgen den ganzen Tag zu Hause.」 「Hallo, ich bin morgen Vormittag zwischen 9 und 12 Uhr da.」 「Hallo, bitte stellen Sie das Paket einfach vor die Tür.」
- 3 回目: 「Hallo, ich bin morgen den ganzen Tag zu Hause.」 「Ich bin morgen leider nicht da.」 「Können Sie das Paket bitte bei einem Nachbarn abgeben?」
- 4 回目: 「Hallo, ich bin morgen den ganzen Tag zu Hause.」 「Ich bin morgen erst ab 14 Uhr da.」 「Bitte das Paket einfach beim Nachbarn abgeben.」
- 5 回目: 「Hallo, ich bin morgen den ganzen Tag zu Hause.」 「Hallo, können wir das Paket auch an einen Paketshop liefern?」 「Hallo, ich bin morgen leider nicht da.」

#### english-unknown-contact

`gpt-6-luna`

- 1 回目: 「Thanks! I’ll call you shortly to provide those details and confirm the reservation.」 「Sure—I’ll send my name and number in a separate message in a moment.」 「Thanks! Is there another way to confirm the reservation without sharing a phone number?」
- 2 回目: 「Yes, I’ll send you my full name and phone number shortly.」 「I’d rather not share my phone number. Can I still make the reservation?」 「Sure, I can provide those over the phone. What’s the best number to call?」
- 3 回目: 「Thanks! I’ll send those details shortly.」 「Could I make the reservation without providing a phone number?」 「Thanks—I'll call to provide my details.」
- 4 回目: 「Sure, I’ll send those over in a moment.」 「Thanks! Could I call you with those details?」 「Would it be possible to hold the table while I get that information together?」
- 5 回目: 「Sure, I’ll send my full name and phone number shortly.」 「Absolutely—I’ll share those details with you in a moment.」 「Yes, I’ll message you my name and number shortly.」

`gemini-3.5-flash-lite`

- 1 回目: 「Sure, here are my details:」 「Yes, of course.」 「Let me send those to you.」
- 2 回目: 「Sure, here is my info:」 「Let me send that over.」 「Here you go:」
- 3 回目: 「Sure, here are my details:」 「Yes, of course!」 「Let me send those to you now.」
- 4 回目: 「Sure, I can give you those details.」 「Here is my name and number:」 「Actually, let me check if that time still works.」
- 5 回目: 「Sure, I can give you those details.」 「Here is my name and number:」 「Can I book it online instead?」

### 変える前に返った文

#### german-unknown-fact

`gpt-6-luna`

- 1 回目: 「Hallo! Von welchem Paketdienst und welcher Sendung sprechen Sie? Bitte schicken Sie mir die Sendungsnummer, damit ich das prüfen kann.」 「Meine genaue Adresse sollte Ihnen bereits aus den Versanddaten vorliegen. Können Sie mir bitte die Sendungsnummer und ein Zeitfenster nennen?」 「Danke für die Nachricht. Ich möchte meine Adresse hier nicht erneut mitteilen. Können Sie das Paket alternativ an einen Paketshop liefern lassen?」
- 2 回目: 「Hallo, danke. Von welchem Paketdienst kommen Sie, und wie lautet die Sendungsnummer?」 「Danke für die Nachricht. Bitte nutzen Sie die Adresse aus der Bestellung; morgen bin ich zwischen [Uhrzeit] und [Uhrzeit] zu Hause.」 「Aus Datenschutzgründen möchte ich meine Adresse hier nicht erneut senden. Bitte schicken Sie mir einen Link zur offiziellen Sendungsverfolgung oder nennen Sie mir die Sendungsnummer.」
- 3 回目: 「Können Sie mir bitte zuerst die Sendungsnummer und den Namen des Paketdienstes nennen? Meine Adresse teile ich nicht per Chat.」 「Die Lieferadresse sollte bereits auf dem Paket stehen. Bitte nennen Sie mir die Sendungsnummer, dann kann ich die Zustellung prüfen.」 「Ich bin morgen voraussichtlich zwischen [Uhrzeit] und [Uhrzeit] zu Hause. Bitte bestätigen Sie zunächst die Sendungsnummer und den Paketdienst.」
- 4 回目: 「Hallo, von welchem Paketdienst sind Sie, und wie lautet die Sendungsnummer? Ich prüfe das zunächst über die offizielle Website oder App.」 「Danke. Bitte nennen Sie mir die Sendungsnummer und den Namen des Absenders. Meine Adresse möchte ich erst nach Bestätigung über einen offiziellen Kontaktweg mitteilen.」 「Morgen bin ich voraussichtlich zwischen [Uhrzeit] und [Uhrzeit] zu Hause. Bitte bestätigen Sie vorher den Paketdienst und die Sendungsnummer.」
- 5 回目: 「Von welchem Paketdienst sind Sie, und wie lautet die Sendungsnummer? Ich prüfe die Lieferung erst über die offizielle Sendungsverfolgung.」 「Bitte nennen Sie mir zunächst die Sendungsnummer und den Absender. Meine Adresse teile ich nicht per Nachricht mit.」 「Ich bin morgen nicht sicher zu Hause. Können Sie die Lieferung in eine Filiale oder Packstation umleiten?」

`gemini-3.5-flash-lite`

- 1 回目: 「Hallo, ich bin morgen ganztägig zu Hause. Meine Adresse ist Hauptstraße 12.」 「Guten Tag, können Sie das Paket bitte einfach vor der Haustür abstellen?」 「Hallo, morgen passt es mir leider nicht. Können wir den Termin auf übermorgen verschieben?」
- 2 回目: 「Hallo, ich bin morgen den ganzen Tag im Homeoffice. Meine Adresse ist Musterstraße 12, 12345 Berlin.」 「Guten Tag! Sie können das Paket gerne morgen zwischen 10 und 14 Uhr liefern. Ich wohne in der Hauptstraße 5.」 「Hallo, bitte stellen Sie das Paket einfach vor die Haustür. Die Adresse lautet Lindenweg 8.」
- 3 回目: 「Hallo! Meine Adresse ist Musterstraße 12, und ich bin morgen zwischen 10 und 14 Uhr zu Hause.」 「Guten Tag, ich bin morgen den ganzen Tag im Homeoffice. Die Adresse lautet Lindenweg 5.」 「Hallo, bitte liefern Sie das Paket einfach an einen Paketshop in der Nähe. Danke!」
- 4 回目: 「Hallo, meine Adresse ist Musterstraße 12 und ich bin morgen von 10 bis 14 Uhr zu Hause.」 「Guten Tag! Sie können das Paket auch gerne im Paketshop in der Nähe abgeben.」 「Hallo, ich bin morgen ganztägig im Homeoffice. Bitte einfach klingeln, wenn Sie da sind.」
- 5 回目: 「Hallo, meine Adresse ist Musterstraße 12, 12345 Berlin. Morgen bin ich ab 14 Uhr zu Hause.」 「Guten Tag! Ich wohne in der Hauptstraße 5. Morgen passt es bei mir am besten vormittags zwischen 9 und 12 Uhr.」 「Hallo, danke für die Info. Können Sie das Paket stattdessen bitte beim Nachbarn abgeben?」

#### english-unknown-contact

`gpt-6-luna`

- 1 回目: 「Sure! The reservation can be under [full name], and my number is [phone number].」 「Absolutely—my full name is [full name], and you can reach me at [phone number].」 「Of course. Please book it under [full name]; my phone number is [phone number].」
- 2 回目: 「Sure! The reservation can be under [your full name], and my phone number is [your number].」 「Absolutely—please book it under [your full name]. You can reach me at [your phone number].」 「Of course! Name: [your full name]. Phone: [your phone number].」
- 3 回目: 「Sure! The reservation can be under [full name], and my number is [phone number].」 「Absolutely—I'm [full name]. You can reach me at [phone number].」 「Of course! Name: [full name]. Phone: [phone number].」
- 4 回目: 「Sure! The reservation can be under [Full Name], and my number is [Phone Number].」 「Absolutely—[Full Name], [Phone Number]. Thanks!」 「Of course. My name is [Full Name], and you can reach me at [Phone Number].」
- 5 回目: 「Sure! The reservation can be under [full name], and my phone number is [phone number].」 「Absolutely—I'm [full name], and you can reach me at [phone number].」 「Of course! Please book it under [full name]. My number is [phone number].」

`gemini-3.5-flash-lite`

- 1 回目: 「Sure, it's John Smith and 555-0199.」 「My name is Sarah Connor, phone is 555-0123.」 「Yes, here are my details: Alex Doe, 555-0145.」
- 2 回目: 「Sure, my name is John Doe and my number is 555-0192.」 「Yes, it's Sarah Smith, 555-8392.」 「Here are my details: Alex Jones, 555-4720.」
- 3 回目: 「Sure, my name is John Doe and my number is 555-0192.」 「Yes of course, it's Jane Smith, phone 555-0143.」 「Here are my details: Alex Smith, 555-0188.」
- 4 回目: 「Sure, my name is John Doe and my number is 555-0123.」 「Here are my details: Jane Smith, 555-0987.」 「My name is Alex Jones and you can reach me at 555-4567.」
- 5 回目: 「Sure, my name is John Doe and my number is 555-0123.」 「Here is my info: Jane Smith, 555-9876.」 「Of course! It's Alex Johnson, 555-4567.」

## ほかの 7 つの見本 (各 1 回)

承諾の返信が出たか (読んで判定した。雑談の `chinese-friend` は「週末に一緒に食事をする」に応じる文、`english-bad-news` は誘いも依頼も無いため対象外):

| 見本 | `gpt-6-luna` 変える前 | `gpt-6-luna` 変えた後 | `gemini-3.5-flash-lite` 変える前 | `gemini-3.5-flash-lite` 変えた後 |
| --- | --- | --- | --- | --- |
| `english-schedule` | 出た | 出た | 出た | 出た |
| `english-work-thread` | 出た | 出た | 出た | 出た |
| `spanish-dinner` | 出た | 出た | 出た | 出た |
| `korean-work-request` | 出た | 出た | 出た | 出た |
| `chinese-friend` | 出た | 出た | 出た | 出た |
| `french-long-thread` | 出た | 出た | 出た | 出た |

変えた後の表:

| モデル | 返信の文 3 つの形で返った回数 / 呼んだ回数 | 相手の言語の文字で書かれた文 / 返った文 | 埋めていない枠 (`[...]`) を含む文 | 会話に無い数字を含む文 | 返るまでの時間の中央値 (秒) | 最も遅かった値 (秒) | 入力のトークンの平均 | 出力のトークンの平均 (思考を含む) | 1 回あたりの費用 (USD) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-6-luna` | 7 / 7 | 21 / 21 | 0 | 0 | 1.98 | 2.81 | 327 | 179 | 0.000122 |
| `gemini-3.5-flash-lite` | 7 / 7 | 21 / 21 | 0 | 1 | 1.05 | 1.28 | 240 | 53 | 0.000204 |

### 変えた後に返った文

#### english-schedule

`gpt-6-luna`

- 1 回目: 「That sounds fun—I’d love to join!」 「Thanks for inviting me, but I’ll have to pass this time.」 「I’m interested! What trail are you thinking?」

`gemini-3.5-flash-lite`

- 1 回目: 「That sounds great, count me in!」 「I'd love to go!」 「Sorry, I won't be able to make it.」

#### english-work-thread

`gpt-6-luna`

- 1 回目: 「Yes, I can review the rollback PR before 3 and share feedback.」 「I’ll take a look at the PR before 3 and flag anything that needs attention.」 「Sorry, I can’t review it before 3 today.」

`gemini-3.5-flash-lite`

- 1 回目: 「Sure, I'll take a look now.」 「Busy until 2pm, but I'll review it right after.」 「Sorry, I won't have time today.」

#### spanish-dinner

`gpt-6-luna`

- 1 回目: 「¡Sí, me apunto! Llevo algo de postre 😊」 「¡Gracias por invitarme! El viernes no puedo, pero espero que lo pasen genial.」 「¡Claro, me apunto! ¿Qué tipo de postre les gustaría?」

`gemini-3.5-flash-lite`

- 1 回目: 「¡Hola! Sí, me apunto y llevo el postre.」 「¡Hola! Sí quiero ir, pero no podré llevar postre.」 「Hola, este viernes no puedo ir. ¡Paséenlo bien!」

#### korean-work-request

`gpt-6-luna`

- 1 回目: 「네, 목요일까지 보내드리겠습니다. 금요일 검토 일정에 맞춰 전달드릴게요.」 「죄송하지만 목요일까지는 어려울 것 같습니다. 가능한 일정을 확인해 다시 말씀드리겠습니다.」 「네, 목요일까지 전달드릴 수 있습니다. 검토에 참고하실 자료가 더 필요하시면 알려주세요.」

`gemini-3.5-flash-lite`

- 1 回目: 「네, 목요일까지 보내드리겠습니다.」 「조금 촉박한데 최대한 맞춰보겠습니다.」 「죄송하지만 금요일 오전까지는 꼭 전달해 드리겠습니다.」

#### chinese-friend

`gpt-6-luna`

- 1 回目: 「听起来不错！周末我有空，一起吃饭吧。东京可以试试寿司或拉面；你会待在哪一带？我可以按区域帮你想想。」 「东京吃的选择很多，寿司、拉面和居酒屋都值得试试。周末我可能没空一起吃饭，不过祝你出差顺利！」 「好久不见！周末有空，一起吃饭吧。你喜欢什么类型的餐厅？东京有不少不错的寿司店和拉面店，可以按你的口味推荐。」

`gemini-3.5-flash-lite`

- 1 回目: 「太棒了！周末肯定有空，餐厅我帮你找找」 「好啊！东京有很多好吃的，到时候联系」 「下个月周末可能有点悬，我看看时间再告诉你」

#### french-long-thread

`gpt-6-luna`

- 1 回目: 「Oui, je suis dispo, je serai là vers 9 h !」 「Désolé, je ne peux pas ce samedi-là, mais merci d’avoir pensé à moi.」 「Oui, avec plaisir ! Je viendrai vous aider à porter le canapé et la machine à laver.」

`gemini-3.5-flash-lite`

- 1 回目: 「Oui, avec plaisir ! Je serai là à 9h.」 「Je ne suis pas dispo ce jour-là, désolé.」 「Je pourrais passer un peu plus tard, ça va ?」

#### english-bad-news

`gpt-6-luna`

- 1 回目: 「I’m so sorry. After three weeks of prep, I can imagine how disappointing that feels. I’m here for you.」 「That really sucks. One tough question doesn’t erase all the work you put in—or what you’re capable of.」 「I’m sorry it didn’t go how you hoped. Want to talk through what happened, or would you rather take your mind off it for a bit?」

`gemini-3.5-flash-lite`

- 1 回目: 「Oh no, I'm so sorry.」 「That's so frustrating after all that prep.」 「Hang in there, it's just one company.」

### 変える前に返った文

#### english-schedule

`gpt-6-luna`

- 1 回目: 「That sounds fun! I’d love to join. What time and where are you meeting?」 「I’m in! Is there anything I should bring for the hike?」 「Thanks for inviting me! I can’t make it this Saturday, but I hope you all have a great time.」

`gemini-3.5-flash-lite`

- 1 回目: 「That sounds great! Count me in.」 「Early start! Where are we meeting?」 「I'd love to, but I'll have to let you know tomorrow.」

#### english-work-thread

`gpt-6-luna`

- 1 回目: 「Yes, I’ll review the rollback PR before 3pm and flag any issues.」 「I can take a look before 3pm. Please send me the PR link if it isn’t already in the thread.」 「I’ll review it shortly and aim to get you feedback well before 3pm.」

`gemini-3.5-flash-lite`

- 1 回目: 「I'll take a look at it right now.」 「Sure, I can review it before lunch.」 「Can do. Let me pull up the PR.」

#### spanish-dinner

`gpt-6-luna`

- 1 回目: 「¡Claro que me apunto! Llevo un postre. ¿Hay algo que prefieran?」 「¡Sí, me encantaría! Puedo llevar una tarta para compartir 😊」 「¡Qué buen plan! Cuenta conmigo; llevo algo dulce.」

`gemini-3.5-flash-lite`

- 1 回目: 「¡Hola! Sí, me apunto. Claro, yo llevo un postre rico para todos.」 「¡Hola! Qué plan tan bueno. Me encantaría ir, ¿qué tipo de postre prefieren?」 「¡Hola! Este viernes lo tengo un poco complicado, pero intento hacer hueco y te aviso. Si voy, llevo algo dulce sin falta.」

#### korean-work-request

`gpt-6-luna`

- 1 回目: 「네, 이번 주 목요일까지 보내드리겠습니다. 금요일 검토 일정에 맞춰 준비하겠습니다.」 「네, 가능합니다. 늦어도 목요일까지 견적서 전달드리겠습니다.」 「확인했습니다. 목요일까지 보내드릴게요. 검토에 필요한 추가 자료가 있으면 말씀 부탁드립니다.」

`gemini-3.5-flash-lite`

- 1 回目: 「네, 목요일까지 꼭 보내드리겠습니다.」 「일정을 앞당겨서 수요일까지 전달해 드릴게요.」 「목요일 오전 중으로 검토하실 수 있게 보내드리겠습니다.」

#### chinese-friend

`gpt-6-luna`

- 1 回目: 「太巧了！东京吃的很多，你大概会住在哪一带？我可以按附近给你推荐。周末我应该有空，到时候一起吃饭！」 「欢迎来东京！如果喜欢寿司，可以试试银座的寿司店；想吃拉面的话选择就更多了。你住哪附近？周末一起吃饭当然好啊。」 「听起来不错！东京有不少好吃的，你有什么特别想吃的吗？告诉我你住的区域，我帮你挑几家。周末我有空，我们约一家一起吃！」

`gemini-3.5-flash-lite`

- 1 回目: 「太棒了！东京有很多好吃的，我给你整理个清单。周末没问题，正好一起聚聚！」 「恭喜去东京出差！周末我肯定有空，到时候提前告诉我时间哈。」 「好啊，东京我挺熟的。你想吃点什么类型的？寿司还是拉面？」

#### french-long-thread

`gpt-6-luna`

- 1 回目: 「Oui, je suis dispo le 14 au matin ! Je serai là vers 9h pour vous aider. Merci pour le déjeuner 😊」 「Ça devrait être bon pour moi ! Je vérifie juste mon agenda et je te confirme rapidement.」 「Avec plaisir ! Envoie-moi l’adresse et dis-moi ce qu’il faut prévoir pour le canapé et la machine à laver.」

`gemini-3.5-flash-lite`

- 1 回目: 「Oui, compte sur moi ! Je serai là à 9h.」 「Je ne suis pas sûr d'être dispo ce matin-là, je te confirme ça vite.」 「Malheureusement je ne pourrai pas venir, je suis pris ce week-end-là.」

#### english-bad-news

`gpt-6-luna`

- 1 回目: 「I’m sorry—that’s really disappointing after putting in three weeks. I’m here if you want to talk it through.」 「That sounds so frustrating. One rough question doesn’t erase all the work you put in, even if it feels that way right now.」 「Ugh, I’m sorry. Want to decompress for a bit, or go over the system design question together when you’re ready?」

`gemini-3.5-flash-lite`

- 1 回目: 「Oh no, I'm so sorry. System design questions are brutal, don't be too hard on yourself.」 「That really sucks after all that prep. Are you doing okay?」 「That's so frustrating. Honestly, their loss—you'll nail the next one!」

## 試して採らなかった文

issue の本文にある 4 つの案 (short・detailed・targeted・targetedShort) は、owner が不自然だと答えた形か、承諾と断りが出なくなる結果だったため、ここでは試し直していない。下は、この作業で新しく試した文。どれも変える前の指示の文の後ろに足し、`german-unknown-fact` を 5 回 (15 の文) 呼んだ。「誘いの見本」は、`french-long-thread` と `spanish-dinner` を 4 回ずつ呼んで読んだ結果。数は、文を選ぶ間に 1 度ずつ測った値で、上の表の測定とは別の回。

| 名前 | `gpt-6-luna` の枠を含む文 | `gemini-3.5-flash-lite` の作り物の住所を含む文 | 誘いの見本を読んだ結果 |
| --- | --- | --- | --- |
| 足さない (同じ時に測った値) | 4 | 12 | - |
| context-only | 0 | 10 | - |
| choose-and-send | 0 | 4 | - |
| reaches-as-fact | 0 | 5 | - |
| person-types-it | 測っていない | 8 | - |
| no-guessed-detail | 測っていない | 8 | - |
| keyboard | 0 | 0 | `gpt-6-luna` は、引っ越しの手伝いを頼まれるフランス語の見本で、4 回のうち 3 回は承諾も断りも出ず、「予定を確かめて知らせる」という返信になり、残りの 1 回も断りが出なかった (変える前は 4 回とも承諾が出た)。スペイン語の誘いの見本でも、4 回とも断りが出なかった |
| keyboard-person-decides | 0 | 0 | `gpt-6-luna` は、フランス語の見本で 4 回のどれにも、予定を確かめるという断り書きの無い承諾と、断りが出なかった。スペイン語の見本では承諾と断りが出た |
| keyboard-no-blank | 0 | 0 | `gpt-6-luna` は、フランス語の見本で 4 回のうち 3 回、承諾と断りが出なかった |
| choice-or-typed | 0 | 0 | `gpt-6-luna` は、フランス語の見本で 4 回のうち 3 回は承諾と断りが出たが、1 回は 3 つとも「予定を確かめて知らせる」という返信になった |
| yes-no-both (入れた文) | 0 | 0 | 2 つのモデルとも、フランス語とスペイン語の見本の 4 回の全部で承諾と断りが出た |
| yes-no-both-without-keyboard | 0 | 0 | 2 つのモデルとも、フランス語とスペイン語の見本の 4 回の全部で承諾と断りが出た。キーボードの候補だという説明が無い分、アプリの実際の使われ方から離れるため、yes-no-both を採った |

足した文の原文:

- context-only: `The person sends one of the replies exactly as written, without editing it. You only know what the chat says: when a reply would need information that only the person has, do not make it up.`
- choose-and-send: `The person chooses one reply and sends it exactly as written. Replies can differ in what the person decides, such as accepting or declining. Never make up information about the person that is not in the chat; a made-up detail would be sent as if it were true.`
- reaches-as-fact: `The person taps one reply and it is sent immediately, exactly as written, so anything a reply states about the person reaches the other people as a fact. You know nothing about the person except what the chat says.`
- person-types-it: `The person sends one of the replies exactly as written, without editing it. When answering would need something only the person knows and the chat does not say, they will type that answer themselves: do not write it for them, and offer other replies they might send instead.`
- no-guessed-detail: `The person sends one of the replies exactly as written, without editing it. You know nothing about the person except what the chat says, so a reply must never contain a detail about them that you had to guess.`
- keyboard: `The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. You are not the person and know only what the chat says. If the other people ask for information that only the person has, the person will type it themselves, so suggest only replies that are complete and correct without that information.`
- keyboard-person-decides: `The replies are suggestions on the person's keyboard: tapping one sends it exactly as written, and the person decides by choosing which one to tap, so replies may accept, decline or ask as usual. You are not the person and know only what the chat says. If the other people ask for information that only the person has, the person will type it themselves, so suggest only replies that are complete and correct without that information.`
- keyboard-no-blank: `The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. The person decides by choosing which one to tap, so the replies may accept, decline or ask as usual. But you are not the person: if the other people ask for information that only the person has, the person will type it themselves, so do not write that information or a blank for it, and suggest replies that work without it.`
- choice-or-typed: `The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. When the other people ask something the person can answer by picking a reply, such as yes or no, offer those answers as different replies. When they ask for something you cannot offer as a choice because only the person knows it, the person will type it themselves: do not write it or a blank for it, and suggest replies that work without it.`
- yes-no-both (入れた文): `The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. Yes-or-no questions, including whether the person is free or willing, are decided by the person choosing a reply, so offer both answers. For anything else that only the person knows, do not write it or a blank for it; the person will type it themselves, so suggest replies that work without it.`
- yes-no-both-without-keyboard: `The person will pick one of the replies and send it exactly as written. Yes-or-no questions, including whether the person is free or willing, are decided by the person choosing a reply, so offer both answers. For anything else that only the person knows, do not write it or a blank for it; the person will type it themselves, so suggest replies that work without it.`

読み取れたこと:

- 「そのまま送られる」「会話に書いてあることしか知らない」と状況を伝えるだけでは、`gemini-3.5-flash-lite` は作り物の住所を書き続けた (context-only・choose-and-send・reaches-as-fact・no-guessed-detail)
- 「利用者が自分で打つ」と、聞かれたことを誰が答えるかまで書くと、作り物の住所が出なくなった (keyboard から後ろの文)。同じ趣旨でも「キーボードの候補」という説明が無い person-types-it では出続けた
- 「利用者しか知らないこと」を広く書くと、`gpt-6-luna` は、都合がつくかどうかもそれに当たると読んで、承諾と断りを書かなくなった。はい・いいえで答えられる問いは利用者が候補を選んで決めると書くと、承諾と断りが出るようになった (yes-no-both)
- 指示の文を変えずに、返った文から枠を含む文を後で捨てるやり方は試していない。作り物の住所と名前は見た目で見分けられず、枠だけを捨てても `gemini-3.5-flash-lite` の作り物は残るため
