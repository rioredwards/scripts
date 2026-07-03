from enum import Enum


class TaskTags(Enum):
    leetcode = "Leetcode"
    website = "Website"
    desktop_app = "Desktop App"
    script = "Script"
    backend = "Backend"
    database = "Database"
    cloud = "Cloud"

# holds tasks with their task tags and time_frames
task_list = [
    {"name": "Two Sum", "task_tag": TaskTags.leetcode, "time_frame": 60},
    {"name": "Reverse String", "task_tag": TaskTags.leetcode, "time_frame": 60},
    {"name": "Contains Duplicate", "task_tag": TaskTags.leetcode, "time_frame": 60},
    {"name": "Valid Anagram", "task_tag": TaskTags.leetcode, "time_frame": 90},
    {"name": "Group Anagrams", "task_tag": TaskTags.leetcode, "time_frame": 90},
    {
        "name": "Top K Frequent Elements",
        "task_tag": TaskTags.leetcode,
        "time_frame": 60,
    },
    {
        "name": "Valid Palindrome",
        "task_tag": TaskTags.leetcode,
        "time_frame": 60,
    },
    {
        "name": "3Sum",
        "task_tag": TaskTags.leetcode,
        "time_frame": 90,
    },
    {
        "name": "Container With Most Water",
        "task_tag": TaskTags.leetcode,
        "time_frame": 120,
    },
    {
        "name": "Best Time to Buy And Sell Stock",
        "task_tag": TaskTags.leetcode,
        "time_frame": 90,
    },
    {
        "name": "Longest Substring Without Repeating Characters",
        "task_tag": TaskTags.leetcode,
        "time_frame": 90,
    },
    {
        "name": "Valid Parentheses",
        "task_tag": TaskTags.leetcode,
        "time_frame": 60,
    },
    {
        "name": "Reverse Linked List",
        "task_tag": TaskTags.leetcode,
        "time_frame": 90,
    },
    {
        "name": "Merge Two Sorted Lists",
        "task_tag": TaskTags.leetcode,
        "time_frame": 90,
    },
    {
        "name": "Invert Binary Tree",
        "task_tag": TaskTags.leetcode,
        "time_frame": 120,
    },
    {
        "name": "Maximum Depth of Binary Tree",
        "task_tag": TaskTags.leetcode,
        "time_frame": 120,
    },
    {
        "name": "Single Blog",
        "task_tag": TaskTags.website,
        "time_frame": 180,
    },
    {
        "name": "Landing Page",
        "task_tag": TaskTags.website,
        "time_frame": 180,
    },
    {
        "name": "Docs",
        "task_tag": TaskTags.website,
        "time_frame": 240,
    },
    {
        "name": "Todos",
        "task_tag": TaskTags.website,
        "time_frame": 180,
    },
    {
        "name": "Timer",
        "task_tag": TaskTags.website,
        "time_frame": 120,
    },
    {
        "name": "Calculator",
        "task_tag": TaskTags.website,
        "time_frame": 240,
    },
    {
        "name": "Photo Gallery",
        "task_tag": TaskTags.website,
        "time_frame": 120,
    },
    {
        "name": "Authentication Page",
        "task_tag": TaskTags.website,
        "time_frame": 180,
    },
    {
        "name": "Pokedex list from PokeAPI (https://pokeapi.co/) with Searchbar",
        "task_tag": TaskTags.website,
        "time_frame": 240,
    },
    {
        "name": "Star Wars character list from SWAPI (https://swapi.tech/) with Searchbar",
        "task_tag": TaskTags.website,
        "time_frame": 240,
    },
    {
        "name": "Display current weather using wether api (https://www.weatherapi.com/)",
        "task_tag": TaskTags.website,
        "time_frame": 240,
    },
    {
        "name": "Todos",
        "task_tag": TaskTags.desktop_app,
        "time_frame": 240,
    },
    {
        "name": "Calculator",
        "task_tag": TaskTags.desktop_app,
        "time_frame": 300,
    },
    {
        "name": "Timer",
        "task_tag": TaskTags.desktop_app,
        "time_frame": 180,
    },
    {
        "name": "Notes",
        "task_tag": TaskTags.desktop_app,
        "time_frame": 180,
    },
    {
        "name": "Print time",
        "task_tag": TaskTags.script,
        "time_frame": 30,
    },
    {
        "name": "Save / List notes",
        "task_tag": TaskTags.script,
        "time_frame": 120,
    },
    {
        "name": "Find and replace a specified string in a file",
        "task_tag": TaskTags.script,
        "time_frame": 120,
    },
    {
        "name": "Find a file by name and print its path if it exists",
        "task_tag": TaskTags.script,
        "time_frame": 120,
    },
    {
        "name": "Word count for a file or from stdin",
        "task_tag": TaskTags.script,
        "time_frame": 90,
    },
    {
        "name": "Print current temperature outside",
        "task_tag": TaskTags.script,
        "time_frame": 120,
    },
    {
        "name": "CRUD API for Todos",
        "task_tag": TaskTags.backend,
        "time_frame": 240,
    },
    {
        "name": "CRUD API for Blog Posts",
        "task_tag": TaskTags.backend,
        "time_frame": 240,
    },
    {
        "name": "Realtime Chat",
        "task_tag": TaskTags.backend,
        "time_frame": 300,
    },
    {
        "name": "Return current weather using wether api (https://www.weatherapi.com/)",
        "task_tag": TaskTags.backend,
        "time_frame": 180,
    },
    {
        "name": "Return movie list from movie api (https://www.themoviedb.org/)",
        "task_tag": TaskTags.backend,
        "time_frame": 180,
    },
    {
        "name": "ChatGPT interface",
        "task_tag": TaskTags.backend,
        "time_frame": 300,
    },
    {
        "name": "Return relevant youtube videos for a given search term",
        "task_tag": TaskTags.backend,
        "time_frame": 300,
    },
    {
        "name": "Stripe API",
        "task_tag": TaskTags.backend,
        "time_frame": 300,
    },
    {
        "name": "Twilio API",
        "task_tag": TaskTags.backend,
        "time_frame": 300,
    },
    {
        "name": "Todos DB",
        "task_tag": TaskTags.database,
        "time_frame": 120,
    },
    {
        "name": "Users DB",
        "task_tag": TaskTags.database,
        "time_frame": 120,
    },
    {
        "name": "Video games DB",
        "task_tag": TaskTags.database,
        "time_frame": 120,
    },
    {
        "name": "Plants",
        "task_tag": TaskTags.cloud,
        "time_frame": 120,
    },
    {
        "name": "Stocks",
        "task_tag": TaskTags.cloud,
        "time_frame": 120,
    },
    {
        "name": "Cars",
        "task_tag": TaskTags.cloud,
        "time_frame": 120,
    },
]
