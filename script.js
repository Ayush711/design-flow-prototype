// Global variable to store markdown for download
let generatedMarkdown = '';

/**
 * Main function to handle file upload and processing
 */
function handleFile() {
    const fileInput = document.getElementById('fileInput');
    const loading = document.getElementById('loading');
    const error = document.getElementById('error');
    const outputSection = document.getElementById('outputSection');
    const downloadSection = document.getElementById('downloadSection');

    // Reset states
    error.classList.add('hidden');
    outputSection.classList.add('hidden');
    downloadSection.classList.add('hidden');
    generatedMarkdown = '';

    // Validation: Check if file is selected
    if (!fileInput.files || fileInput.files.length === 0) {
        showError('Please select a CSV file first.');
        return;
    }

    const file = fileInput.files[0];

    // Validation: Check file type
    if (!file.name.toLowerCase().endsWith('.csv')) {
        showError('Please upload a valid CSV file.');
        return;
    }

    // Show loading state
    loading.classList.remove('hidden');

    // Read file using FileReader
    const reader = new FileReader();

    reader.onload = function(e) {
        try {
            const csvText = e.target.result;

            // Parse CSV to JSON
            const data = parseCSV(csvText);

            if (data.length === 0) {
                showError('No valid data found in the CSV file.');
                loading.classList.add('hidden');
                return;
            }

            // Group by domain
            const groupedData = groupByDomain(data);

            // Generate summary
            const summary = generateSummary(data, groupedData);

            // Generate markdown
            generatedMarkdown = generateMarkdown(groupedData, summary);

            // Render output
            renderOutput(summary, generatedMarkdown);

            // Hide loading, show output
            loading.classList.add('hidden');
            outputSection.classList.remove('hidden');
            downloadSection.classList.remove('hidden');

        } catch (err) {
            showError('Error processing file: ' + err.message);
            loading.classList.add('hidden');
        }
    };

    reader.onerror = function() {
        showError('Error reading file. Please try again.');
        loading.classList.add('hidden');
    };

    reader.readAsText(file);
}

/**
 * Parse CSV string into JSON array
 * @param {string} csv - CSV string content
 * @returns {Array} - Array of objects with domain, event, description
 */
function parseCSV(csv) {
    const lines = csv.split(/\r?\n/).filter(line => line.trim() !== '');

    if (lines.length < 2) {
        return [];
    }

    // Parse header row
    const headers = parseCSVLine(lines[0]).map(h => h.toLowerCase().trim());

    // Find column indices - support various column naming conventions
    const domainIndex = headers.findIndex(h => 
        h.includes('domain') || h.includes('category') || h.includes('epic') || h.includes('milestone')
    );
    const eventIndex = headers.findIndex(h => 
        h.includes('event') || h.includes('name') || h.includes('title') || h.includes('summary') || h.includes('task')
    );
    const descriptionIndex = headers.findIndex(h => 
        h.includes('description') || h.includes('desc') || h.includes('detail') || h.includes('body')
    );
    const statusIndex = headers.findIndex(h => h.includes('status'));

    // If required columns not found, use fallback mapping
    const dIdx = domainIndex >= 0 ? domainIndex : 0;
    const eIdx = eventIndex >= 0 ? eventIndex : (dIdx === 0 ? 1 : 0);
    const descIdx = descriptionIndex >= 0 ? descriptionIndex : 2;

    const data = [];

    // Parse data rows
    for (let i = 1; i < lines.length; i++) {
        const values = parseCSVLine(lines[i]);

        // Skip empty rows or rows with no meaningful data
        if (values.length === 0 || values.every(v => !v.trim())) {
            continue;
        }

        const event = (values[eIdx] || '').trim();
        const domain = (values[dIdx] || 'Uncategorized').trim();
        const description = (values[descIdx] || 'No description available').trim();
        const status = statusIndex >= 0 ? (values[statusIndex] || '').trim() : '';

        // Skip rows without an event/title
        if (!event) {
            continue;
        }

        data.push({
            domain: domain || 'Uncategorized',
            event: event,
            description: description + (status ? ` [Status: ${status}]` : '')
        });
    }

    return data;
}

/**
 * Parse a single CSV line handling quoted values
 * @param {string} line - CSV line
 * @returns {Array} - Array of values
 */
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
                i++; // Skip next quote
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

/**
 * Group events by domain
 * @param {Array} data - Array of event objects
 * @returns {Object} - Object with domains as keys and arrays of events as values
 */
function groupByDomain(data) {
    const grouped = {};

    data.forEach(item => {
        const domain = item.domain || 'Uncategorized';

        if (!grouped[domain]) {
            grouped[domain] = [];
        }

        grouped[domain].push({
            event: item.event,
            description: item.description
        });
    });

    return grouped;
}

/**
 * Generate summary text
 * @param {Array} data - Original data array
 * @param {Object} groupedData - Grouped data object
 * @returns {string} - Summary text
 */
function generateSummary(data, groupedData) {
    const domainCount = Object.keys(groupedData).length;
    const eventCount = data.length;

    return `This system contains ${domainCount} domain${domainCount !== 1 ? 's' : ''} and ${eventCount} event${eventCount !== 1 ? 's' : ''}.`;
}

/**
 * Generate markdown from grouped data
 * @param {Object} groupedData - Grouped data object
 * @param {string} summary - Summary text
 * @returns {string} - Markdown string
 */
function generateMarkdown(groupedData, summary) {
    let markdown = `# Design Flow Document\n\n`;
    markdown += `> ${summary}\n\n`;
    markdown += `---\n\n`;

    const domains = Object.keys(groupedData).sort();

    domains.forEach(domain => {
        markdown += `## Domain: ${domain}\n\n`;

        groupedData[domain].forEach(item => {
            markdown += `* **Event: ${item.event}**\n`;
            markdown += `  Description: ${item.description}\n\n`;
        });

        markdown += `---\n\n`;
    });

    markdown += `\n*Generated on ${new Date().toLocaleDateString()} at ${new Date().toLocaleTimeString()}*\n`;

    return markdown;
}

/**
 * Render output to the page
 * @param {string} summary - Summary text
 * @param {string} markdown - Markdown content
 */
function renderOutput(summary, markdown) {
    const summaryEl = document.getElementById('summary');
    const outputEl = document.getElementById('output');

    summaryEl.textContent = summary;

    // Use marked.js to convert markdown to HTML
    if (typeof marked !== 'undefined') {
        outputEl.innerHTML = marked.parse(markdown);
    } else {
        // Fallback: basic markdown rendering
        outputEl.innerHTML = `<pre>${markdown}</pre>`;
    }
}

/**
 * Download design as markdown file
 */
function downloadDesign() {
    if (!generatedMarkdown) {
        showError('No design to download. Please upload a CSV file first.');
        return;
    }

    // Create Blob
    const blob = new Blob([generatedMarkdown], { type: 'text/markdown;charset=utf-8' });

    // Create download link
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'design.md';

    // Trigger download
    document.body.appendChild(link);
    link.click();

    // Cleanup
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
}

/**
 * Show error message
 * @param {string} message - Error message to display
 */
function showError(message) {
    const error = document.getElementById('error');
    error.textContent = message;
    error.classList.remove('hidden');
}

// Add drag and drop support
document.addEventListener('DOMContentLoaded', function() {
    const fileInput = document.getElementById('fileInput');
    const uploadArea = fileInput.parentElement;

    // Prevent default drag behaviors
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        uploadArea.addEventListener(eventName, preventDefaults, false);
        document.body.addEventListener(eventName, preventDefaults, false);
    });

    function preventDefaults(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    // Highlight drop area when dragging over
    ['dragenter', 'dragover'].forEach(eventName => {
        uploadArea.addEventListener(eventName, highlight, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
        uploadArea.addEventListener(eventName, unhighlight, false);
    });

    function highlight() {
        fileInput.style.borderColor = '#667eea';
        fileInput.style.background = '#f0f4ff';
    }

    function unhighlight() {
        fileInput.style.borderColor = '#ddd';
        fileInput.style.background = '';
    }

    // Handle dropped files
    uploadArea.addEventListener('drop', function(e) {
        const dt = e.dataTransfer;
        const files = dt.files;

        if (files.length > 0) {
            fileInput.files = files;
        }
    }, false);
});
