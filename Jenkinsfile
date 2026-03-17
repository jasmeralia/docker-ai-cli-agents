pipeline {
  agent any

  triggers {
    cron('TZ=America/Los_Angeles\nH 4 1 * *')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    GIT_AUTHOR_NAME = 'jenkins'
    GIT_AUTHOR_EMAIL = 'jenkins@local'
    GIT_COMMITTER_NAME = 'jenkins'
    GIT_COMMITTER_EMAIL = 'jenkins@local'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Detect Versions') {
      steps {
        script {
          def report = readJSON text: sh(
            script: 'make check-versions',
            returnStdout: true
          ).trim()

          env.CURRENT_CODEX = report.codex.current
          env.LATEST_CODEX = report.codex.latest
          env.CURRENT_CCUSAGE = report.ccusage.current
          env.LATEST_CCUSAGE = report.ccusage.latest
          env.CURRENT_CODEX_USAGE = report.codex_usage.current
          env.LATEST_CODEX_USAGE = report.codex_usage.latest
          env.CURRENT_CLAUDE = report.claude.current
          env.LATEST_CLAUDE = report.claude.latest
          env.CODEX_CHANGED = report.codex.changed.toString()
          env.CCUSAGE_CHANGED = report.ccusage.changed.toString()
          env.CODEX_USAGE_CHANGED = report.codex_usage.changed.toString()
          env.CLAUDE_CHANGED = report.claude.changed.toString()
        }
      }
    }

    stage('Update Versions') {
      when {
        expression {
          env.CODEX_CHANGED == 'true' ||
          env.CCUSAGE_CHANGED == 'true' ||
          env.CODEX_USAGE_CHANGED == 'true' ||
          env.CLAUDE_CHANGED == 'true'
        }
      }
      steps {
        sh '''
          make update-versions UPDATE_ARGS="\
            --codex-version ${LATEST_CODEX} \
            --ccusage-version ${LATEST_CCUSAGE} \
            --codex-usage-version ${LATEST_CODEX_USAGE} \
            --claude-version ${LATEST_CLAUDE} \
            --bump-release patch"
        '''
      }
    }

    stage('Commit And Tag') {
      when {
        expression {
          env.CODEX_CHANGED == 'true' ||
          env.CCUSAGE_CHANGED == 'true' ||
          env.CODEX_USAGE_CHANGED == 'true' ||
          env.CLAUDE_CHANGED == 'true'
        }
      }
      steps {
        script {
          def releaseVersion = readJSON file: 'versions.json'
          env.RELEASE_VERSION = releaseVersion.release_version
        }

        sh '''
          git add versions.json
          git commit -m "chore: update CLI versions (codex ${LATEST_CODEX}, ccusage ${LATEST_CCUSAGE}, codex usage ${LATEST_CODEX_USAGE}, claude ${LATEST_CLAUDE})"
          git tag "v${RELEASE_VERSION}"
          git push origin HEAD
          git push origin "v${RELEASE_VERSION}"
        '''
      }
    }
  }
}
