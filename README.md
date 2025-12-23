# 🔄 Jamf-GitSync 🔄

Created by: Trenton Cook

> ⚠️ **WARNING**  
> This script is intended to be run in an automated environment.  
> I am not responsible for any damage to your GitHub repository or Jamf instance.  
> **Run at your own risk and test before deploying to production.**

## 🔭 Overview

JGS is a tool designed to be hosted in a GitHub environment and used to implement Git version control into your Jamf Pro instance. Being as Jamf Pro has no built in option for version controlling your scripts this is a happy medium that is lightweight, secure, and easy to setup.

### 🖥️ Core Features

- Controlled through a GitHub action
- Able to download and manage up to 2000 Jamf scripts
- Completely automated with no middleman interaction required
- Utilizes GitHub secrets to handle API credentials
- Easy and semi-automated setup
- Updates Jamf hosted script versions quickly

### ✅ Requirements

- Jamf instance
- GitHub Repo to hold scripts (admin access)
- Jamf API role and client with the following privileges:
  - Read Scripts
  - Update Scripts
  - Create Scripts

## 🔧 Setup

### API Roles and Clients
Let's get started by creating an API Role and Client within Jamf Pro, we'll use these generated credentials to authenticate to our Jamf Pro instance and gather a bearer token for use in the *jamfGitSync* script.

Log in to your Jamf Pro instance and navigate to the settings cog on the left-hand side of the screen, in the search bar search for `API roles and clients` and select the option that appears under `System`

Once you're in the API roles and clients page you can select `New` in the top right under the `API Roles` tab, this will create a new API Role that we can assign privileges to. Enter an appropriate name in the `Display Name` section (I used `JamfGitSync`) and start typing out the privileges above listed in the requirements section. *Read Scripts | Update Scripts | Create Scripts. Once you have all three privileges assigned to your new role, you can select `Save` in the bottom right to create our new role.

Now, under the `API Clients` tab select `New` in the top right once more. This will create a new API client we can use to authenticate to our Jamf Pro instance with. Give it a name in the `Display Name` field (I used `JamfGitSync` here again) and under the `API roles` section add that role we just created. To be safe, I adjusted the `Access token lifetime` field to 360 (five minutes) so there are no failures in the script due to expiring tokens. The script will invalidate the tokens at the end of the run anyways so any time left over doesn't have to run out. Now select `Enable API client` and then `Save` in the bottom right.

On your new API client, select `Generate client secret` and confirm. This will generate a client ID and client Secret, be sure to save these to a safe spot for use later!

### GitHub Secrets
Open up the repo that you plan to store these scripts in, and click `Settings` in the top menu bar. Open the `Secrets and Variables` dropdown in the left hand side, and select `Actions`. We're going to create four different secrets for use in the script. For each of them click `New repository secret` and enter the following details

1. **JAMF_CLIENT_ID**  
   Client ID generated in Jamf

2. **JAMF_CLIENT_SECRET**  
   Client secret generated in Jamf

3. **JAMF_URL**  
   https://yourcompany.jamfcloud.com

### JamfGitSync\.sh
Download the [JamfGitSync\.sh](https://github.com/Tc00k/automatedJamf-GitSync/blob/main/jamfGitSync.sh) script in this repository and add it as a file to your repository, ensure that debugMode is set to `true` inside the script before we move on. Otherwise nothing else should be adjusted in the script as it is set to use the secrets we've created from GitHub.

### GitHub Structure
For readability and simplicity's sake, it's easiest to place JamfGitSync\.sh in the main directory of your repo, and create an adjacent directory to hold all of your Jamf scripts. I named my folder quite literally `jamfScripts`

### GitHub Action
In the same repository, select the `Actions` tab in the top menu bar. Inside the Actions page, select `New Workflow` in the top left and select the `Simple Workflow`. Inside the Jamf-GitSync repository there is a [workflow.yml](https://github.com/Tc00k/automatedJamf-GitSync/blob/main/workflow.yml) file. Copy the contents of this over into your new workflow. Now let's give it a name! In the top left of your new workflow file, rename `blank.yml` to something of your choice. I used macSync.yml but whatever you choose just make sure to memorize it or write it down somewhere for later use!

Now that we've given it a name, let's make it yours! Inside of your new workflow YAML file we need to adjust a few lines to match your environment.

Line 7: This line sets the path to watch for commits in order to trigger the automated syncing, this needs to be set to the folder you have holding your Jamf scripts in your GitHub repository. If you followed my example above it should be set to jamfScripts/**

Line 27: This line checks to make sure your jamfGitSync\.sh script is executable, it needs to be set to the path of your jamfGitSync\.sh respectively. If you followed my examples above it should be set to jamfGitSync\.sh

Line 38: This line sets the workingDirectory variable in the script, in other words, where you're storing all your Jamf scripts in your repository. If you followed my example it should be set to ${{ github.workspace }}/jamfScripts

Line 39: This line actually runs your jamfGitSync\.sh. If you followed my examples it should be set to /opt/homebrew/bin/bash ./jamfGitSync.sh

Line 48: This line sets where the GitHub action should check for new scripts to commit and push. If you followed my examples it should be set to git add jamfScripts/*.sh

---
### First Run
Alright! Now that all that's out of the way, let's run our action one time. Double, triple, and quadruple check that the jamfGitSync\.sh script is set to debugmode="true" that way we aren't breaking anything in our Jamf instance if there was a missed step or broken setup. Now, go to `Actions` in your repository one more time. In the left-hand side there should be an entry for your workflow that was just created with whatever name you gave it, if you left the workflow\.yml name line alone it should show as `Mac Sync`. Go ahead and click on that bad boy.

In the top right, you should see a `Run workflow` button. This will manually start our new workflow and kick off our script, once everything is setup and finalized you won't have to do this manually anymore as it should trigger anytime there is a commit inside of your jamfScripts folder. For now, click that button and watch your workflow take off! You can select your workflow run and view the log output to make sure that everything is running smoothly, in fact I highly recommend you read through this log file in its entirety AT LEAST once to check for any warnings or errors.

After your workflow completes successfully you should see that your jamfScripts directory in your repository has been populated with all of your Jamf Scripts. Does everything look good? Great! Time to enable it for real...

### Finalizing (Obligatory Warning *again*)
It goes without saying (but I'll say it anyway) when you set this up and run it in an automated fashion there is always the risk that something could break and wreak havoc. I HIGHLY recommend backing up your Jamf scripts periodically so that you always have a set of scripts that is untainted. This is also something that you setup and run at your own risk and I am not responsible for any damage that this could cause to either your GitHub repository OR your Jamf instance, with that said, I am always available to help on the Mac Admins Slack and would be happy to assist you in setting this up/troubleshooting.

With that ominous warning aside, if you have ran your new workflow manually and everything went smoothly with no errors it's time to open your jamfGitSync\.sh and change debugMode to false. This will enable the updateJamf functionality, meaning that any changes you commit to your scripts in GitHub will be recognized by the runner and uploaded to your Jamf instance.
