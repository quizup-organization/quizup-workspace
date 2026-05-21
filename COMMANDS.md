```bash
find . -type f \( -name "*.java" \) \
  | grep -iv "/target/" \
  | while read f; do
    ext="${f##*.}"
    echo "### $f" >> resultat.md
    echo "\`\`\`$ext" >> resultat.md
    cat "$f" >> resultat.md
    echo "\`\`\`" >> resultat.md
    echo "" >> resultat.md
  done
```

```bash
find . -type d \( -name "node_modules" -o -name "build" -o -name "dist" \) -prune -o \
  -type f \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.css" \) -print \
  | while read f; do
    echo "### $f" >> resultat.md
    echo '```tsx' >> resultat.md
    cat "$f" >> resultat.md
    echo '```' >> resultat.md
    echo "" >> resultat.md
  done
```