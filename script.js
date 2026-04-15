let generatedMarkdown = '';

const appState = {
    currentStep: 1,
    parsed: false,
    planReady: false,
    data: [],
    groupedData: {},
    summary: '',
    insights: null
};

document.addEventListener('DOMContentLoaded', () => {
    bindEvents();
    setupDragDrop();
    updateStepper(1);
});

function bindEvents() {
    document.getElementById('analyzeBtn').addEventListener('click', processDesignInput);
    document.getElementById('presenterToggle').addEventListener('click', togglePresenterMode);
    document.getElementById('toStep2').addEventListener('click', () => goToStep(2));
    document.getElementById('backToStep1').addEventListener('click', () => goToStep(1));
    document.getElementById('runPlanBtn').addEventListener('click', runPlanningFlow);
    document.getElementById('toStep3').addEventListener('click', () => {
        if (!appState.planReady) {
            showError('Run planning flow before moving to delivery pack.');
            return;
        }
        goToStep(3);
    });
    document.getElementById('backToStep2').addEventListener('click', () => goToStep(2));
    document.getElementById('downloadBtn').addEventListener('click', downloadDesign);
}

function togglePresenterMode() {
    const panel = document.getElementById('presenterPanel');
    const toggle = document.getElementById('presenterToggle');
    const willShow = panel.classList.contains('hidden');

    panel.classList.toggle('hidden', !willShow);
    toggle.textContent = willShow ? 'Disable Presenter Mode' : 'Enable Presenter Mode';
    toggle.setAttribute('aria-expanded', String(willShow));

    if (willShow) {
        updateCriteriaStatus();
    }
}

function processDesignInput() {
    const fileInput = document.getElementById('fileInput');
    const loading = document.getElementById('loading');

    clearMessages();

    if (!fileInput.files || fileInput.files.length === 0) {
        showError('Please select a CSV file first.');
        return;
    }

    const file = fileInput.files[0];
    if (!file.name.toLowerCase().endsWith('.csv')) {
        showError('Please upload a valid CSV file.');
        return;
    }

    loading.classList.remove('hidden');

    const reader = new FileReader();
    reader.onload = function (e) {
        try {
            const csvText = e.target.result;
            const data = parseCSV(csvText);

            if (data.length === 0) {
                throw new Error('No valid data found in the CSV file.');
            }

            const groupedData = groupByDomain(data);
            const summary = generateSummary(data, groupedData);
            const insights = calculateInsights(data, groupedData);

            appState.data = data;
            appState.groupedData = groupedData;
            appState.summary = summary;
            appState.insights = insights;
            appState.parsed = true;
            appState.planReady = false;

            generatedMarkdown = generateMarkdown(groupedData, summary, insights);
            renderBuildPlan();
            renderDeliveryPack();
            resetRunboard();

            document.getElementById('toStep2').disabled = false;
            loading.classList.add('hidden');
            showSuccess('Design input analyzed successfully. Continue to build planning.');
            updateCriteriaStatus();
        } catch (err) {
            loading.classList.add('hidden');
            showError('Error processing file: ' + err.message);
        }
    };

    reader.onerror = function () {
        loading.classList.add('hidden');
        showError('Error reading file. Please try again.');
    };

    reader.readAsText(file);
}

function goToStep(step) {
    if (step > 1 && !appState.parsed) {
        showError('Complete step 1 before moving forward.');
        return;
    }

    appState.currentStep = step;
    ['step-1', 'step-2', 'step-3'].forEach((id, idx) => {
        const el = document.getElementById(id);
        if (!el) return;
        if (idx + 1 === step) {
            el.classList.remove('hidden');
        } else {
            el.classList.add('hidden');
        }
    });

    updateStepper(step);
    clearMessages();
}

function updateStepper(step) {
    document.querySelectorAll('.step').forEach((stepBtn) => {
        const btnStep = Number(stepBtn.dataset.step);
        stepBtn.classList.remove('active', 'complete');
        if (btnStep < step) {
            stepBtn.classList.add('complete');
        }
        if (btnStep === step) {
            stepBtn.classList.add('active');
        }
    });
}

function runPlanningFlow() {
    if (!appState.parsed || !appState.insights) {
        showError('Please complete design intake first.');
        return;
    }

    clearMessages();
    const runPlanBtn = document.getElementById('runPlanBtn');
    const toStep3 = document.getElementById('toStep3');

    runPlanBtn.disabled = true;
    runPlanBtn.textContent = 'Running...';
    resetRunboard();

    setAgentStatus('agent-design', 'running', 'Running');
    setTimeout(() => {
        setAgentStatus('agent-design', 'done', 'Complete');
        setAgentStatus('agent-architecture', 'running', 'Running');
    }, 600);

    setTimeout(() => {
        setAgentStatus('agent-architecture', 'done', 'Complete');
        setAgentStatus('agent-delivery', 'running', 'Running');
    }, 1200);

    setTimeout(() => {
        setAgentStatus('agent-delivery', 'done', 'Complete');
        appState.planReady = true;
        toStep3.disabled = false;
        runPlanBtn.disabled = false;
        runPlanBtn.textContent = 'Run Planning Flow';
        showSuccess('Planning flow complete. Delivery pack is ready.');
        renderDeliveryPack();
        updateCriteriaStatus();
    }, 1800);
}

function setAgentStatus(id, statusClass, text) {
    const el = document.getElementById(id);
    if (!el) return;
    el.className = `badge ${statusClass}`;
    el.textContent = text;
}

function resetRunboard() {
    setAgentStatus('agent-design', 'pending', 'Pending');
    setAgentStatus('agent-architecture', 'pending', 'Pending');
    setAgentStatus('agent-delivery', 'pending', 'Pending');
    document.getElementById('toStep3').disabled = true;
}

function renderBuildPlan() {
    const { domainCount, eventCount, estimatedHours, complexityScore, eventsPerDomain } = appState.insights;

    document.getElementById('kpiDomains').textContent = String(domainCount);
    document.getElementById('kpiEvents').textContent = String(eventCount);
    document.getElementById('kpiHours').textContent = `${estimatedHours}h`;
    document.getElementById('kpiComplexity').textContent = String(complexityScore);

    const domainCoverage = document.getElementById('domainCoverage');
    domainCoverage.innerHTML = '';

    eventsPerDomain.forEach((item) => {
        const li = document.createElement('li');
        li.innerHTML = `<span>${escapeHtml(item.domain)}</span><strong>${item.count} events</strong>`;
        domainCoverage.appendChild(li);
    });
}

function renderDeliveryPack() {
    const outputEl = document.getElementById('output');
    const executiveSummary = document.getElementById('executiveSummary');
    const insights = appState.insights;

    if (!insights) return;

    executiveSummary.innerHTML = `
        <h3>Executive Summary</h3>
        <p>${appState.summary}</p>
        <p>Estimated process model effort is <strong>${insights.estimatedHours} hours</strong>, based on event volume and domain spread. Planning status: <strong>${appState.planReady ? 'Ready for delivery' : 'Awaiting planning run'}</strong>.</p>
    `;

    if (typeof marked !== 'undefined') {
        outputEl.innerHTML = marked.parse(generatedMarkdown);
    } else {
        outputEl.textContent = generatedMarkdown;
    }
}

function calculateInsights(data, groupedData) {
    const domainNames = Object.keys(groupedData);
    const domainCount = domainNames.length;
    const eventCount = data.length;
    const averageEventsPerDomain = domainCount ? eventCount / domainCount : 0;

    // Simple prototype estimate model:
    // base analysis + per domain planning + per event modeling + complexity factor
    const estimatedHours = Math.max(4, Math.round(6 + domainCount * 2.5 + eventCount * 1.35 + averageEventsPerDomain * 0.8));
    const complexityScore = Math.round(domainCount * 1.8 + eventCount * 0.7);

    const eventsPerDomain = domainNames
        .map((domain) => ({ domain, count: groupedData[domain].length }))
        .sort((a, b) => b.count - a.count);

    return {
        domainCount,
        eventCount,
        estimatedHours,
        complexityScore,
        eventsPerDomain
    };
}

function parseCSV(csv) {
    const lines = csv.split(/\r?\n/).filter((line) => line.trim() !== '');
    if (lines.length < 2) return [];

    const headers = parseCSVLine(lines[0]).map((h) => h.toLowerCase().trim());
    const domainIndex = headers.findIndex((h) => h.includes('domain') || h.includes('category') || h.includes('epic') || h.includes('milestone'));
    const eventIndex = headers.findIndex((h) => h.includes('event') || h.includes('name') || h.includes('title') || h.includes('summary') || h.includes('task'));
    const descriptionIndex = headers.findIndex((h) => h.includes('description') || h.includes('desc') || h.includes('detail') || h.includes('body'));
    const statusIndex = headers.findIndex((h) => h.includes('status'));

    const dIdx = domainIndex >= 0 ? domainIndex : 0;
    const eIdx = eventIndex >= 0 ? eventIndex : (dIdx === 0 ? 1 : 0);
    const descIdx = descriptionIndex >= 0 ? descriptionIndex : 2;

    const data = [];

    for (let i = 1; i < lines.length; i++) {
        const values = parseCSVLine(lines[i]);
        if (values.length === 0 || values.every((v) => !v.trim())) continue;

        const event = (values[eIdx] || '').trim();
        const domain = (values[dIdx] || 'Uncategorized').trim();
        const description = (values[descIdx] || 'No description available').trim();
        const status = statusIndex >= 0 ? (values[statusIndex] || '').trim() : '';

        if (!event) continue;

        data.push({
            domain: domain || 'Uncategorized',
            event,
            description: description + (status ? ` [Status: ${status}]` : '')
        });
    }

    return data;
}

function parseCSVLine(line) {
    const values = [];
    let current = '';
    let inQuotes = false;

    for (let i = 0; i < line.length; i++) {
        const char = line[i];
        const nextChar = line[i + 1];

        if (char === '"') {
            if (inQuotes && nextChar === '"') {
                current += '"';
                i++;
            } else {
                inQuotes = !inQuotes;
            }
        } else if (char === ',' && !inQuotes) {
            values.push(current.trim());
            current = '';
        } else {
            current += char;
        }
    }

    values.push(current.trim());
    return values;
}

function groupByDomain(data) {
    const grouped = {};
    data.forEach((item) => {
        const domain = item.domain || 'Uncategorized';
        if (!grouped[domain]) grouped[domain] = [];
        grouped[domain].push({ event: item.event, description: item.description });
    });
    return grouped;
}

function generateSummary(data, groupedData) {
    const domainCount = Object.keys(groupedData).length;
    const eventCount = data.length;
    return `This design model contains ${domainCount} domain${domainCount !== 1 ? 's' : ''} and ${eventCount} event${eventCount !== 1 ? 's' : ''}.`;
}

function generateMarkdown(groupedData, summary, insights) {
    let markdown = '# Design Flow Document\n\n';
    markdown += `> ${summary}\n\n`;
    markdown += `> Estimated Process Model Hours: ${insights.estimatedHours}h | Complexity Score: ${insights.complexityScore}\n\n`;
    markdown += '---\n\n';

    const domains = Object.keys(groupedData).sort();
    domains.forEach((domain) => {
        markdown += `## Domain: ${domain}\n\n`;
        groupedData[domain].forEach((item) => {
            markdown += `* **Event: ${item.event}**\n`;
            markdown += `  Description: ${item.description}\n\n`;
        });
        markdown += '---\n\n';
    });

    markdown += `*Generated on ${new Date().toLocaleDateString()} at ${new Date().toLocaleTimeString()}*\n`;
    return markdown;
}

function downloadDesign() {
    if (!generatedMarkdown) {
        showError('No design to download. Please upload and analyze a CSV first.');
        return;
    }

    const blob = new Blob([generatedMarkdown], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'design.md';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    markCriteriaPass('criteria-delivery', 'Pass');
}

function setupDragDrop() {
    const fileInput = document.getElementById('fileInput');
    const uploadArea = document.getElementById('uploadArea');

    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach((eventName) => {
        uploadArea.addEventListener(eventName, preventDefaults, false);
        document.body.addEventListener(eventName, preventDefaults, false);
    });

    ['dragenter', 'dragover'].forEach((eventName) => {
        uploadArea.addEventListener(eventName, () => uploadArea.classList.add('drag-active'), false);
    });

    ['dragleave', 'drop'].forEach((eventName) => {
        uploadArea.addEventListener(eventName, () => uploadArea.classList.remove('drag-active'), false);
    });

    uploadArea.addEventListener('drop', (e) => {
        const files = e.dataTransfer.files;
        if (files.length > 0) {
            fileInput.files = files;
        }
    }, false);
}

function preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
}

function clearMessages() {
    document.getElementById('error').classList.add('hidden');
    document.getElementById('success').classList.add('hidden');
}

function showError(message) {
    const error = document.getElementById('error');
    error.textContent = message;
    error.classList.remove('hidden');
}

function showSuccess(message) {
    const success = document.getElementById('success');
    success.textContent = message;
    success.classList.remove('hidden');
}

function updateCriteriaStatus() {
    markCriteriaStatus('criteria-intake', appState.parsed ? 'pass' : 'pending');
    markCriteriaStatus('criteria-metrics', appState.parsed && !!appState.insights ? 'pass' : 'pending');
    markCriteriaStatus('criteria-planning', appState.planReady ? 'pass' : (appState.parsed ? 'running' : 'pending'));
    markCriteriaStatus('criteria-delivery', generatedMarkdown ? 'ready' : 'pending');
}

function markCriteriaPass(id, text) {
    const el = document.getElementById(id);
    if (!el) return;
    el.className = 'criteria-status pass';
    el.textContent = text;
}

function markCriteriaStatus(id, state) {
    const el = document.getElementById(id);
    if (!el) return;

    const map = {
        pending: { className: 'criteria-status pending', text: 'Pending' },
        running: { className: 'criteria-status running', text: 'In Progress' },
        ready: { className: 'criteria-status ready', text: 'Ready' },
        pass: { className: 'criteria-status pass', text: 'Pass' }
    };

    const selected = map[state] || map.pending;
    el.className = selected.className;
    el.textContent = selected.text;
}

function escapeHtml(str) {
    return String(str)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}
