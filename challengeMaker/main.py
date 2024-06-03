#!/usr/bin/env python3
import random
import tech
import task

task_list = task.task_list
tech_list = tech.tech_list

chosen_tech = random.choice(tech_list)

filtered_tasks = list(
    filter(
        lambda task: (task["task_tag"] in chosen_tech["task_tags"]),
        task_list,
    )
)

if len(filtered_tasks) == 0:
    print(f"No tasks found for {chosen_tech['name']}")
    exit(1)

chosen_task = random.choice(filtered_tasks)


def color_string(string, color):
    colors = {
        "black": "\033[60m",
        "red": "\033[31m",
        "green": "\033[32m",
        "yellow": "\033[33m",
        "blue": "\033[34m",
        "magenta": "\033[35m",
        "cyan": "\033[36m",
        "white": "\033[37m",
        "reset": "\033[0m",
    }
    if color not in colors:
        return string  # Return the original string if the color is not supported
    return f"{colors[color]}{string}{colors['reset']}"


colored_tech_string = color_string(chosen_tech["name"], "blue")
colored_task_string = color_string(chosen_task["name"], "red")
colored_task_tag_string = color_string(chosen_task["task_tag"].value, "cyan")
colored_time_string = color_string(str(chosen_task["time_frame"]), "yellow")

challenge_string = f"{colored_task_tag_string} Challenge: {colored_task_string} using {colored_tech_string} in {colored_time_string} minutes"

print(challenge_string)
