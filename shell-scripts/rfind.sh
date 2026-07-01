#!/bin/bash

# Smart Repository Search Script
# Searches through repositories with intelligent scoring and ranking

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
MIN_SCORE=5
MAX_RESULTS=20
SEARCH_DEPTH=10

# Helper function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to calculate relevance score
calculate_score() {
    local path=$1
    shift
    local keywords=("$@")
    local score=0
    local path_lower=$(echo "$path" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')
    
    # Split path into components
    local basename=$(basename "$path")
    local dirname=$(dirname "$path")
    local basename_lower=$(echo "$basename" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')
    local dirname_lower=$(echo "$dirname" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')
    
    for keyword in "${keywords[@]}"; do
        local keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        
        # Exact basename match (highest priority)
        if [[ "$basename_lower" == "$keyword_lower" ]]; then
            ((score += 100))
        fi
        
        # Basename contains keyword (high priority)
        if [[ "$basename_lower" == *"$keyword_lower"* ]]; then
            ((score += 50))
        fi
        
        # Directory name contains keyword (medium priority)
        if [[ "$dirname_lower" == *"$keyword_lower"* ]]; then
            ((score += 25))
        fi
        
        # Full path contains keyword (lower priority)
        if [[ "$path_lower" == *"$keyword_lower"* ]]; then
            ((score += 10))
        fi
        
        # Stricter fuzzy match (prefix/word-boundary instead of loose regex)
        if echo "$basename_lower" | grep -iq "\b$keyword_lower"; then
            ((score += 15))
        fi
    done
    
    # Bonus for multiple keyword matches in same path
    local match_count=0
    for keyword in "${keywords[@]}"; do
        local keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if [[ "$path_lower" == *"$keyword_lower"* ]]; then
            ((match_count++))
        fi
    done
    
    if [[ $match_count -gt 1 ]]; then
        ((score += match_count * 20))
    fi
    
    # Penalize deeply nested files (prefer higher-level matches)
    local depth=$(echo "$path" | tr -cd '/' | wc -c)
    ((score -= depth * 2))
    
    echo "$score"
}

# Function to search for content within files
search_file_content() {
    local file=$1
    shift
    local keywords=("$@")
    local content_score=0
    
    # Only search text files, skip binaries
    if file "$file" 2>/dev/null | grep -qi "text"; then
        for keyword in "${keywords[@]}"; do
            local count=$(grep -iow "$keyword" "$file" 2>/dev/null | wc -l)
            # Diminishing returns for repetition
            if [[ $count -gt 0 ]]; then
                ((content_score += 10 + count * 2))
                if [[ $count -gt 5 ]]; then
                    ((content_score += 10)) # Bonus for high relevance
                fi
            fi
        done
    fi
    
    echo "$content_score"
}

# Function to get file type icon
get_icon() {
    local path=$1
    
    if [[ -d "$path" ]]; then
        echo "📁"
    elif [[ -f "$path" ]]; then
        case "${path##*.}" in
            js|jsx|ts|tsx) echo "📜" ;;
            py) echo "🐍" ;;
            sh|bash) echo "🔧" ;;
            md|txt) echo "📄" ;;
            json|yaml|yml|toml) echo "⚙️" ;;
            html|css|scss) echo "🎨" ;;
            java) echo "☕" ;;
            go) echo "🔷" ;;
            rs) echo "🦀" ;;
            *) echo "📄" ;;
        esac
    else
        echo "❓"
    fi
}

# Main search function
search_repo() {
    local start_dir=${1:-.}
    shift
    local keywords=("$@")
    
    print_color "$CYAN" "${BOLD}🔍 Searching for: ${keywords[*]}${NC}\n"
    
    # Create temporary file for results
    local temp_results=$(mktemp)
    
    # Find all files and directories
    find "$start_dir" -maxdepth "$SEARCH_DEPTH" 2>/dev/null | \
    grep -v '/\.' | \
    grep -v '/node_modules/' | \
    grep -v '/venv/' | \
    grep -v '/__pycache__/' | \
    grep -v '/dist/' | \
    grep -v '/build/' | \
    grep -v '/target/' | \
    grep -v "$(basename "$0")" | while read -r path; do
        
        # Calculate path score
        local path_score=$(calculate_score "$path" "${keywords[@]}")

        # Skip weak/noisy matches early
        if [[ $path_score -lt 15 ]]; then
            continue
        fi
        
        # Calculate content score for files
        local content_score=0
        if [[ -f "$path" ]] && [[ $path_score -gt 0 ]]; then
            content_score=$(search_file_content "$path" "${keywords[@]}")
        fi
        
        local total_score=$((path_score + content_score))
        
        if [[ $total_score -gt $MIN_SCORE ]]; then
            echo "$total_score|$path|$path_score|$content_score" >> "$temp_results"
        fi
    done
    
    # Sort by score and display results
    if [[ -s "$temp_results" ]]; then
        print_color "$GREEN" "${BOLD}📊 Top Results (sorted by relevance):${NC}\n"
        
        # Create sorted file
        local sorted_file=$(mktemp)
        sort -t'|' -k1 -rn "$temp_results" | head -n "$MAX_RESULTS" > "$sorted_file"
        
        local count=0
        while IFS='|' read -r score path path_score content_score; do
            ((++count))
            local icon=$(get_icon "$path")
            local rel_path=${path#$start_dir/}
            
            # Color code based on score
            local score_color=$YELLOW
            if [[ $score -gt 100 ]]; then
                score_color=$GREEN
            elif [[ $score -gt 50 ]]; then
                score_color=$CYAN
            fi
            
            print_color "$score_color" "${BOLD}#$count [Score: $score]${NC}"
            echo -e "  $icon  $rel_path"
            
            print_color "$BLUE" "     └─ Path match: $path_score | Content match: $content_score"
            echo ""
        done < "$sorted_file"
        
        rm -f "$sorted_file"
        
        local total_matches=$(wc -l < "$temp_results")
        print_color "$MAGENTA" "\n✨ Found $total_matches total matches, showing top $count"
    else
        print_color "$RED" "❌ No matches found for: ${keywords[*]}"
    fi
    
    rm -f "$temp_results"
}

# Interactive mode
interactive_search() {
    print_color "$CYAN" "${BOLD}🎯 Smart Repository Search${NC}\n"
    
    # Get search directory
    read -p "$(echo -e ${YELLOW}Enter directory to search [default: current directory]: ${NC})" search_dir
    search_dir=${search_dir:-.}
    
    if [[ ! -d "$search_dir" ]]; then
        print_color "$RED" "❌ Directory does not exist: $search_dir"
        exit 1
    fi
    
    # Get keywords
    print_color "$YELLOW" "Enter search keywords (space-separated):"
    read -p "> " keywords_input
    
    if [[ -z "$keywords_input" ]]; then
        print_color "$RED" "❌ No keywords provided"
        exit 1
    fi
    
    # Convert to array
    read -ra keywords <<< "$keywords_input"
    
    # Optional: configure search depth
    read -p "$(echo -e ${YELLOW}Max search depth [default: 10]: ${NC})" depth_input
    SEARCH_DEPTH=${depth_input:-10}
    
    # Optional: configure max results
    read -p "$(echo -e ${YELLOW}Max results to show [default: 20]: ${NC})" results_input
    MAX_RESULTS=${results_input:-20}
    
    echo ""
    search_repo "$search_dir" "${keywords[@]}"
}

# Main script logic
main() {
    if [[ $# -eq 0 ]]; then
        # No arguments, run interactive mode
        interactive_search
    else
        # Command line arguments provided
        search_repo "." "$@"
    fi
}

# Run main
main "$@"