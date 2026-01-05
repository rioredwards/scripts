#!/usr/bin/env node
const { Client } = require("@notionhq/client");
const commander = require("commander");
const dotenv = require("dotenv");
const fs = require("fs");
const path = require("path");

// Find the project directory (where the .env file is located)
function findProjectDir() {
  // If running from the project directory, use current directory
  if (fs.existsSync(path.join(process.cwd(), '.env'))) {
    return process.cwd();
  }
  
  // If running globally, try to find the project directory
  // Look for the package.json file to identify the project root
  let currentDir = __dirname;
  while (currentDir !== path.dirname(currentDir)) {
    if (fs.existsSync(path.join(currentDir, 'package.json'))) {
      return currentDir;
    }
    currentDir = path.dirname(currentDir);
  }
  
  // Fallback to current directory
  return process.cwd();
}

const projectDir = findProjectDir();
const envPath = path.join(projectDir, '.env');

// Load .env file from project directory
dotenv.config({ path: envPath });

// Check if .env file was found and loaded
if (!process.env.NOTION_TOKEN || !process.env.NOTION_DATABASE_ID) {
  console.error("❌ Environment variables not found!");
  console.error(`📁 Looking for .env file in: ${projectDir}`);
  console.error("💡 Make sure your .env file contains:");
  console.error("   NOTION_TOKEN=your_notion_api_key");
  console.error("   NOTION_DATABASE_ID=your_database_id");
  process.exit(1);
}

const notion = new Client({ auth: process.env.NOTION_TOKEN });

async function addHotkey(app, command, name) {

  try {
    const response = await notion.pages.create({
      parent: {
        type: "database_id",
        database_id: process.env.NOTION_DATABASE_ID,
      },
      properties: {
        App: {
          select: {
            name: app,
          },
        },
        Command: {
          title: [
            {
              text: {
                content: command,
              },
            },
          ],
        },
        Name: {
          rich_text: [
            {
              text: {
                content: name,
              },
            },
          ],
        },
      },
    });
    
    console.log("✅ Hotkey added successfully");
    console.log(`📝 Name: ${name}`);
    console.log(`💻 App: ${app}`);
    console.log(`⌨️  Command: ${command}`);
    console.log(`🔗 URL: ${response.url}`);
    return true;
  } catch (error) {
    console.error("❌ Failed to add hotkey:", error.message);
    return false;
  }
}

async function addMultipleHotkeys(hotkeys) {

  console.log(`🚀 Adding ${hotkeys.length} hotkeys...\n`);
  
  let successCount = 0;
  let failureCount = 0;

  for (let i = 0; i < hotkeys.length; i++) {
    const hotkey = hotkeys[i];
    console.log(`📝 Processing ${i + 1}/${hotkeys.length}: ${hotkey.name}`);
    
    const success = await addHotkey(hotkey.app, hotkey.command, hotkey.name);
    
    if (success) {
      successCount++;
    } else {
      failureCount++;
    }
    
    // Add a small delay to avoid rate limiting
    if (i < hotkeys.length - 1) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    
    console.log(""); // Empty line for readability
  }

  console.log(`🎉 Batch operation completed!`);
  console.log(`✅ Successfully added: ${successCount}`);
  if (failureCount > 0) {
    console.log(`❌ Failed to add: ${failureCount}`);
  }
}

commander
  .command("add")
  .description("Add a hotkey with a name, command, and app")
  .requiredOption("-a, --app <app>", "Application name")
  .requiredOption("-c, --command <command>", "Command or hotkey")
  .requiredOption("-n, --name <name>", "Name for the hotkey")
  .action(async (options) => {
    await addHotkey(options.app, options.command, options.name);
  });

commander
  .command("add-multiple")
  .description("Add multiple hotkeys from a JSON file, JSON string, or command line")
  .option("-f, --file <file>", "JSON file containing hotkeys array")
  .option("-j, --json <json>", "JSON string containing hotkeys array")
  .option("-a, --app <app>", "Application name (for single hotkey)")
  .option("-c, --command <command>", "Command or hotkey (for single hotkey)")
  .option("-n, --name <name>", "Name for the hotkey (for single hotkey)")
  .action(async (options) => {
    let hotkeys = [];

    if (options.file) {
      try {
        const fileContent = fs.readFileSync(options.file, 'utf8');
        const data = JSON.parse(fileContent);
        
        if (Array.isArray(data)) {
          hotkeys = data;
        } else if (data.hotkeys && Array.isArray(data.hotkeys)) {
          hotkeys = data.hotkeys;
        } else {
          console.error("❌ Invalid JSON file format. Expected an array of hotkeys or an object with 'hotkeys' array.");
          return;
        }
      } catch (error) {
        console.error("❌ Error reading JSON file:", error.message);
        return;
      }
    } else if (options.json) {
      try {
        const data = JSON.parse(options.json);
        
        if (Array.isArray(data)) {
          hotkeys = data;
        } else if (data.hotkeys && Array.isArray(data.hotkeys)) {
          hotkeys = data.hotkeys;
        } else {
          console.error("❌ Invalid JSON string format. Expected an array of hotkeys or an object with 'hotkeys' array.");
          return;
        }
      } catch (error) {
        console.error("❌ Error parsing JSON string:", error.message);
        return;
      }
    } else if (options.app && options.command && options.name) {
      // Single hotkey via command line
      hotkeys = [{
        app: options.app,
        command: options.command,
        name: options.name
      }];
    } else {
      console.error("❌ Please provide either a JSON file (-f), JSON string (-j), or all three options: app (-a), command (-c), and name (-n)");
      return;
    }

    if (hotkeys.length === 0) {
      console.error("❌ No hotkeys found to add");
      return;
    }

    await addMultipleHotkeys(hotkeys);
  });

commander.parse(process.argv);
