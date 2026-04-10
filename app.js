const DATA_PATH = "./data/question_bank.cleaned.json";
const STORAGE_KEY = "metallography_quiz_progress_v1";

const state = {
  mode: "sequential",
  allQuestions: [],
  currentPool: [],
  currentIndex: 0,
  currentQuestion: null,
  selected: new Set(),
  submitted: false,
  progress: {
    done: {},
    wrong: {},
    correctCount: 0,
    doneCount: 0,
  },
};

const el = {
  datasetMeta: document.getElementById("datasetMeta"),
  resetBtn: document.getElementById("resetBtn"),
  modeButtons: [...document.querySelectorAll(".mode-btn")],
  progressText: document.getElementById("progressText"),
  accuracyText: document.getElementById("accuracyText"),
  qidBadge: document.getElementById("qidBadge"),
  qtypeBadge: document.getElementById("qtypeBadge"),
  questionText: document.getElementById("questionText"),
  questionMedia: document.getElementById("questionMedia"),
  optionList: document.getElementById("optionList"),
  submitBtn: document.getElementById("submitBtn"),
  showAnswerBtn: document.getElementById("showAnswerBtn"),
  nextBtn: document.getElementById("nextBtn"),
  feedback: document.getElementById("feedback"),
  doneCount: document.getElementById("doneCount"),
  correctCount: document.getElementById("correctCount"),
  wrongCount: document.getElementById("wrongCount"),
};

function loadProgress() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return;
  try {
    const parsed = JSON.parse(raw);
    if (parsed && parsed.done && parsed.wrong) {
      state.progress = parsed;
    }
  } catch (_) {
    // Ignore malformed local cache.
  }
}

function saveProgress() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state.progress));
}

function resetProgress() {
  state.progress = { done: {}, wrong: {}, correctCount: 0, doneCount: 0 };
  saveProgress();
}

function shuffle(array) {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function updatePool() {
  if (state.mode === "wrong") {
    const wrongIds = new Set(Object.keys(state.progress.wrong).map(Number));
    state.currentPool = state.allQuestions.filter((q) => wrongIds.has(q.id));
  } else if (state.mode === "random") {
    state.currentPool = shuffle(state.allQuestions);
  } else {
    state.currentPool = [...state.allQuestions];
  }

  state.currentIndex = 0;
  if (state.currentPool.length === 0) {
    state.currentQuestion = null;
  } else {
    state.currentQuestion = state.currentPool[0];
  }
  state.selected = new Set();
  state.submitted = false;
}

function accuracyPercent() {
  if (!state.progress.doneCount) return 0;
  return Math.round((state.progress.correctCount / state.progress.doneCount) * 100);
}

function refreshSummary() {
  el.doneCount.textContent = String(state.progress.doneCount);
  el.correctCount.textContent = String(state.progress.correctCount);
  el.wrongCount.textContent = String(Object.keys(state.progress.wrong).length);

  el.progressText.textContent = `${Math.min(state.currentIndex + 1, Math.max(state.currentPool.length, 1))} / ${state.currentPool.length}`;
  el.accuracyText.textContent = `正确率 ${accuracyPercent()}%`;
}

function parseAnswer(answer) {
  return new Set((answer || "").split(""));
}

function setFeedback(text, ok) {
  el.feedback.classList.remove("hidden", "ok", "bad");
  el.feedback.textContent = text;
  el.feedback.classList.add(ok ? "ok" : "bad");
}

function hideFeedback() {
  el.feedback.classList.add("hidden");
}

function renderQuestionMedia(images = []) {
  el.questionMedia.innerHTML = "";
  images.forEach((src, idx) => {
    const img = document.createElement("img");
    img.src = src;
    img.loading = "lazy";
    img.alt = `题目配图 ${idx + 1}`;
    el.questionMedia.appendChild(img);
  });
}

function renderQuestion() {
  refreshSummary();
  hideFeedback();
  el.optionList.innerHTML = "";

  const q = state.currentQuestion;
  if (!q) {
    el.qidBadge.textContent = "空";
    el.qtypeBadge.textContent = "无题目";
    el.questionText.textContent = state.mode === "wrong" ? "当前没有错题，继续保持。" : "题库为空。";
    renderQuestionMedia([]);
    return;
  }

  const isMultiple = q.type === "multiple";
  el.qidBadge.textContent = `Q${q.id}`;
  el.qtypeBadge.textContent = isMultiple ? "多选" : "单选";
  el.questionText.textContent = q.question;
  renderQuestionMedia(q.images || []);

  const inputType = isMultiple ? "checkbox" : "radio";
  const inputName = `q-${q.id}`;

  q.options.forEach((opt) => {
    const row = document.createElement("label");
    row.className = "option-item";

    const input = document.createElement("input");
    input.type = inputType;
    input.name = inputName;
    input.value = opt.key;
    input.disabled = state.submitted;
    input.checked = state.selected.has(opt.key);
    input.addEventListener("change", () => {
      if (state.submitted) return;
      if (isMultiple) {
        if (input.checked) state.selected.add(opt.key);
        else state.selected.delete(opt.key);
      } else {
        state.selected = new Set([opt.key]);
        renderQuestion();
      }
    });

    const text = document.createElement("span");
    text.textContent = `${opt.key}. ${opt.text}`;

    row.appendChild(input);
    row.appendChild(text);
    el.optionList.appendChild(row);
  });
}

function markOptions(answerSet, userSet) {
  [...el.optionList.children].forEach((row) => {
    const input = row.querySelector("input");
    const key = input.value;
    row.classList.remove("correct", "wrong");
    if (answerSet.has(key)) {
      row.classList.add("correct");
    } else if (userSet.has(key)) {
      row.classList.add("wrong");
    }
  });
}

function submitAnswer() {
  const q = state.currentQuestion;
  if (!q) return;

  if (state.selected.size === 0) {
    setFeedback("请先选择答案。", false);
    return;
  }

  state.submitted = true;
  const answerSet = parseAnswer(q.answer);
  const userSet = state.selected;

  const user = [...userSet].sort().join("");
  const answer = [...answerSet].sort().join("");
  const isCorrect = user === answer;

  if (!state.progress.done[q.id]) {
    state.progress.doneCount += 1;
    state.progress.done[q.id] = true;
    if (isCorrect) state.progress.correctCount += 1;
  }

  if (isCorrect) {
    delete state.progress.wrong[q.id];
    setFeedback(`回答正确。答案：${q.answer}`, true);
  } else {
    state.progress.wrong[q.id] = true;
    setFeedback(`回答错误。你的答案：${user || "空"}，正确答案：${q.answer}`, false);
  }

  if (q.explanation) {
    el.feedback.textContent += ` 解析：${q.explanation}`;
  }

  markOptions(answerSet, userSet);
  saveProgress();
  refreshSummary();
  renderQuestion();
  markOptions(answerSet, userSet);
}

function showAnswer() {
  const q = state.currentQuestion;
  if (!q) return;
  const answerSet = parseAnswer(q.answer);
  markOptions(answerSet, state.selected);
  setFeedback(`正确答案：${q.answer}${q.explanation ? ` 解析：${q.explanation}` : ""}`, true);
}

function nextQuestion() {
  if (!state.currentQuestion) return;

  if (state.mode === "wrong") {
    const wrongIds = new Set(Object.keys(state.progress.wrong).map(Number));
    state.currentPool = state.allQuestions.filter((q) => wrongIds.has(q.id));
    if (state.currentPool.length === 0) {
      state.currentQuestion = null;
      renderQuestion();
      return;
    }
  }

  state.currentIndex = (state.currentIndex + 1) % state.currentPool.length;
  state.currentQuestion = state.currentPool[state.currentIndex];
  state.selected = new Set();
  state.submitted = false;
  renderQuestion();
}

function bindEvents() {
  el.submitBtn.addEventListener("click", submitAnswer);
  el.showAnswerBtn.addEventListener("click", showAnswer);
  el.nextBtn.addEventListener("click", nextQuestion);

  el.resetBtn.addEventListener("click", () => {
    if (!window.confirm("确认清空做题记录与错题本吗？")) return;
    resetProgress();
    updatePool();
    renderQuestion();
  });

  el.modeButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      state.mode = btn.dataset.mode;
      el.modeButtons.forEach((x) => x.classList.remove("active"));
      btn.classList.add("active");
      updatePool();
      renderQuestion();
    });
  });
}

async function loadData() {
  const resp = await fetch(DATA_PATH);
  if (!resp.ok) {
    throw new Error(`题库加载失败: ${resp.status}`);
  }
  const data = await resp.json();
  state.allQuestions = (data.questions || []).filter((q) => q.options && q.options.length >= 2 && q.answer);
  el.datasetMeta.textContent = `已加载 ${state.allQuestions.length} 题（自动过滤异常题）`;
}

async function bootstrap() {
  loadProgress();
  bindEvents();

  try {
    await loadData();
    updatePool();
    renderQuestion();
  } catch (err) {
    el.datasetMeta.textContent = "题库加载失败";
    el.questionText.textContent = String(err.message || err);
  }

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./service-worker.js").catch(() => {});
  }
}

bootstrap();
