import type { WritingScript } from './benchmarkMeasures.js';

/**
 * 返信の文を作るモデルを比べるための会話の見本 1 つ。
 * 作った会話で、実在の人のチャットではない
 */
export type ConversationSample = {
  /** 見本を見分ける名前。結果の表と文書で使う */
  id: string;
  /** どういう場面の会話か (結果を読む人のための説明) */
  description: string;
  /** 相手の発言 (「Them:」の行) の言語の文字の種類。返信の文が相手の言語で書かれたかを数える時に使う */
  themWritingScript: WritingScript;
  /**
   * 会話の文。アプリの `replyPrompt(messages:)` が作る形 (発言を古い順に並べ、利用者自身の発言に「Me:」、
   * 相手の発言に「Them:」を付けて、発言の間を空行で区切った文)
   */
  conversation: string;
};

/** モデルを比べる時に、どの候補のモデルにも同じものを渡す会話の見本 */
export const conversationSamples: ConversationSample[] = [
  {
    id: 'english-schedule',
    description: '英語。友人との 1 対 1 の予定の相談 (右に寄った吹き出しで利用者自身の発言が見分けられる画面)',
    themWritingScript: 'latin',
    conversation: [
      'Them: Hey! Are you free this Saturday?',
      'Me: I think so. What do you have in mind?',
      'Them: A few of us are going hiking near the lake. We leave around 8am. Want to join?',
    ].join('\n\n'),
  },
  {
    id: 'english-work-thread',
    description:
      '英語。仕事のチャンネル (全員の発言が左に並ぶ画面で、利用者自身の発言を見分けられず、名前と時刻の見出し行が発言の先頭に残る)',
    themWritingScript: 'latin',
    conversation: [
      'Them: Dana Whitfield  10:42 AM\nThe staging deploy failed again on the migration step. Anyone seen this before?',
      'Them: Omar Reyes  10:45 AM\nLooks like the same lock timeout as last week. I can rerun it after lunch.',
      'Them: Dana Whitfield  10:47 AM\n@Kenji can you review the rollback PR before 3pm today? We want to ship the fix this afternoon.',
    ].join('\n\n'),
  },
  {
    id: 'spanish-dinner',
    description: 'スペイン語。友人との夕食の誘い',
    themWritingScript: 'latin',
    conversation: [
      'Them: ¡Hola! ¿Cómo estuvo tu viaje?',
      'Me: Muy bien, gracias. Volví ayer por la noche.',
      'Them: ¡Qué bueno! Oye, el viernes vamos a cenar en casa de Lucía. ¿Te apuntas? Si vienes, ¿puedes traer algo de postre?',
    ].join('\n\n'),
  },
  {
    id: 'korean-work-request',
    description: '韓国語。取引先からの資料の依頼 (丁寧な言い方)',
    themWritingScript: 'hangul',
    conversation: [
      'Them: 안녕하세요, 지난주 회의에서 말씀하신 견적서 건으로 연락드립니다.',
      'Me: 안녕하세요. 네, 준비하고 있습니다.',
      'Them: 감사합니다. 혹시 이번 주 목요일까지 보내주실 수 있을까요? 내부 검토 일정이 금요일이라서요.',
    ].join('\n\n'),
  },
  {
    id: 'chinese-friend',
    description: '中国語 (簡体字)。友人からの近況と質問',
    themWritingScript: 'han',
    conversation: [
      'Them: 好久不见！最近工作忙吗？',
      'Me: 还行，上个月刚换了新项目。',
      'Them: 听起来不错！下个月我要去东京出差，大概待一个星期。有没有推荐的餐厅？周末有空的话一起吃饭吧。',
    ].join('\n\n'),
  },
  {
    id: 'french-long-thread',
    description: 'フランス語。発言の数が多い、引っ越しの手伝いのやり取り',
    themWritingScript: 'latin',
    conversation: [
      'Them: Salut ! Tu te souviens que je déménage le mois prochain ?',
      'Me: Oui bien sûr. Tu as trouvé un appartement finalement ?',
      'Them: Oui, dans le 11e, au quatrième étage sans ascenseur…',
      'Me: Aïe. Tu as beaucoup de meubles ?',
      'Them: Pas tant que ça, mais il y a le canapé et la machine à laver.',
      'Me: Je vois. Tu as loué une camionnette ?',
      'Them: Oui, pour le samedi 14. Est-ce que tu serais disponible pour nous aider le matin ? On commence vers 9h et je paie le déjeuner.',
    ].join('\n\n'),
  },
  {
    id: 'german-unknown-fact',
    description: 'ドイツ語。モデルが知り得ないこと (利用者の住所と到着の時刻) を聞かれる場面。作り話で答えないかを読む',
    themWritingScript: 'latin',
    conversation: [
      'Them: Hallo, hier ist der Paketdienst. Wir haben eine Lieferung für Sie.',
      'Them: Können Sie uns bitte Ihre genaue Adresse und eine Uhrzeit nennen, zu der Sie morgen zu Hause sind?',
    ].join('\n\n'),
  },
  {
    id: 'english-unknown-contact',
    description: '英語。モデルが知り得ないこと (利用者の名前と電話番号) を聞かれる場面。作り話で答えないかを読む',
    themWritingScript: 'latin',
    conversation: [
      'Me: Hi, do you have a table for two this Friday at 7pm?',
      'Them: Hi! Yes, we do. Can I get your full name and a phone number for the reservation?',
    ].join('\n\n'),
  },
  {
    id: 'english-bad-news',
    description: '英語。相手が落ち込んでいる場面 (口調の違う 3 つを書けるかを読む)',
    themWritingScript: 'latin',
    conversation: [
      'Me: How did the interview go?',
      "Them: Not great, honestly. I froze on the system design question and I'm pretty sure I didn't get it.",
      'Them: I spent three weeks preparing for this one.',
    ].join('\n\n'),
  },
];
