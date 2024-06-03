import task

TaskTags = task.TaskTags

general_task_tags = [
    TaskTags.leetcode,
    TaskTags.website,
    TaskTags.desktop_app,
    TaskTags.script,
    TaskTags.backend,
]


simple_task_tags = [
    TaskTags.leetcode,
    TaskTags.script,
]

# holds languages and frameworks and their task tags
tech_list = [
    {
        "name": "Python",
        "task_tags": general_task_tags,
    },
    {
        "name": "JavaScript",
        "task_tags": general_task_tags,
    },
    {
        "name": "HTML/CSS/JS",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Bash",
        "task_tags": [TaskTags.script],
    },
    {
        "name": "TypeScript",
        "task_tags": general_task_tags,
    },
    {
        "name": "Java",
        "task_tags": general_task_tags,
    },
    {
        "name": "C++",
        "task_tags": simple_task_tags,
    },
    {
        "name": "C",
        "task_tags": simple_task_tags,
    },
    {
        "name": "C#",
        "task_tags": general_task_tags,
    },
    {
        "name": "Ruby",
        "task_tags": general_task_tags,
    },
    {
        "name": "Swift",
        "task_tags": [TaskTags.desktop_app, TaskTags.leetcode],
    },
    {
        "name": "Go",
        "task_tags": general_task_tags,
    },
    {
        "name": "Scala",
        "task_tags": simple_task_tags,
    },
    {
        "name": "Kotlin",
        "task_tags": simple_task_tags,
    },
    {
        "name": "Rust",
        "task_tags": simple_task_tags,
    },
    {
        "name": "PHP",
        "task_tags": [TaskTags.backend, TaskTags.website, TaskTags.leetcode],
    },
    {
        "name": "Erlang",
        "task_tags": simple_task_tags,
    },
    {
        "name": "Elixir",
        "task_tags": simple_task_tags,
    },
    {
        "name": "Dart",
        "task_tags": simple_task_tags,
    },
    {
        "name": "React",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Node.js",
        "task_tags": [TaskTags.script, TaskTags.backend, TaskTags.desktop_app],
    },
    {
        "name": "Angular",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Vue",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Svelte-kit",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Express",
        "task_tags": [TaskTags.backend],
    },
    {
        "name": "Next.js",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Nest.js",
        "task_tags": [TaskTags.backend],
    },
    {
        "name": "Hugo",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Django",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Flask",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Spring/Spring Boot",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Ruby on Rails",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "Laravel",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "ASP.NET Core",
        "task_tags": [TaskTags.website],
    },
    {
        "name": "MongoDB",
        "task_tags": [TaskTags.database],
    },
    {
        "name": "PostgreSQL",
        "task_tags": [TaskTags.database],
    },
    {
        "name": "MySQL",
        "task_tags": [TaskTags.database],
    },
    {
        "name": "SQLite",
        "task_tags": [TaskTags.database],
    },
    {
        "name": "Redis",
        "task_tags": [TaskTags.database],
    },
    {
        "name": "Supabase",
        "task_tags": [TaskTags.cloud, TaskTags.database],
    },
    {
        "name": "Firebase",
        "task_tags": [TaskTags.cloud, TaskTags.database],
    },
    {
        "name": "Amazon DynamoDB",
        "task_tags": [TaskTags.cloud, TaskTags.database],
    },
    {
        "name": "Amazon S3",
        "task_tags": [TaskTags.cloud],
    },
    {
        "name": "Elasticsearch",
        "task_tags": [TaskTags.cloud],
    },
]
