#!/usr/bin/bash
# Creates pdf with the images recursively found on directories.
# The images are optimized for the Kindle DXG reader.

# Check for required binaries.
for i in basename convert find sort printf; do
    [ -f "$(which $i)" ] || { echo "Falta $i o no esta en el path."; exit 1;}
done
# We need one dir at least.
[ -d "$1" ] || { echo "$(basename $0) <dir/s>"; exit 1; }
# Stop if there'a any unbound variable.
set -u
# Use a proper color table with a 16 level grayscale.
base64 -d > /tmp/ct16gray.gif <<__EOF__
R0lGODlhEAABAPcAAAAAAAEBAQICAgMDAwQEBAUFBQYGBgcHBwgICAkJCQoKCgsLCwwMDA0NDQ4O
Dg8PDxAQEBERERISEhMTExQUFBUVFRYWFhcXFxgYGBkZGRoaGhsbGxwcHB0dHR4eHh8fHyAgICEh
ISIiIiMjIyQkJCUlJSYmJicnJygoKCkpKSoqKisrKywsLC0tLS4uLi8vLzAwMDExMTIyMjMzMzQ0
NDU1NTY2Njc3Nzg4ODk5OTo6Ojs7Ozw8PD09PT4+Pj8/P0BAQEFBQUJCQkNDQ0REREVFRUZGRkdH
R0hISElJSUpKSktLS0xMTE1NTU5OTk9PT1BQUFFRUVJSUlNTU1RUVFVVVVZWVldXV1hYWFlZWVpa
WltbW1xcXF1dXV5eXl9fX2BgYGFhYWJiYmNjY2RkZGVlZWZmZmdnZ2hoaGlpaWpqamtra2xsbG1t
bW5ubm9vb3BwcHFxcXJycnNzc3R0dHV1dXZ2dnd3d3h4eHl5eXp6ent7e3x8fH19fX5+fn9/f4CA
gIGBgYKCgoODg4SEhIWFhYaGhoeHh4iIiImJiYqKiouLi4yMjI2NjY6Ojo+Pj5CQkJGRkZKSkpOT
k5SUlJWVlZaWlpeXl5iYmJmZmZqampubm5ycnJ2dnZ6enp+fn6CgoKGhoaKioqOjo6SkpKWlpaam
pqenp6ioqKmpqaqqqqurq6ysrK2tra6urq+vr7CwsLGxsbKysrOzs7S0tLW1tba2tre3t7i4uLm5
ubq6uru7u7y8vL29vb6+vr+/v8DAwMHBwcLCwsPDw8TExMXFxcbGxsfHx8jIyMnJycrKysvLy8zM
zM3Nzc7Ozs/Pz9DQ0NHR0dLS0tPT09TU1NXV1dbW1tfX19jY2NnZ2dra2tvb29zc3N3d3d7e3t/f
3+Dg4OHh4eLi4uPj4+Tk5OXl5ebm5ufn5+jo6Onp6erq6uvr6+zs7O3t7e7u7u/v7/Dw8PHx8fLy
8vPz8/T09PX19fb29vf39/j4+Pn5+fr6+vv7+/z8/P39/f7+/v///ywAAAAAEAABAAAIFQD/pZvm
S9UlQnHAPAESYwSGBgACAgA7
__EOF__

# Final resolution to match, the kindle DXG has a 824x1200 screen.
# resolution="786x1136" http://www.mobileread.com/forums/archive/index.php/t-58568.html
resolution="824x1200"

while [ $# -gt 0 ]; do
    outfile="$PWD/$(basename "$1").pdf"
    echo -ne "\e[32m#\n#\tProcessing: '$(basename "$1")'\n#\n\e[m"
    # I'll use natural sorting "sort -V" to get a ordered filelist to process.
    # As i want only one sting i'll remove the newline char with a pipe.
    list=$(find "$1" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.gif' \) -exec echo {} \; | sort -V | tr '\n' '|')
    list=$(printf '%q' "$list")               # Quotemeta the filelist.
    list=$(echo "$list" | sed -e 's/\\|/ /g') # Change our pipe separator back to a non-escaped space.
    escaped_outfile=$(printf '%q' "$outfile") # Also escape our output file.
    # I was unable to do the whols thing at once, so i'll build and evaluate my command later.
    # I'll use an array to be able to document each flag.
#    flags[10]="-fuzz '5%' -trim"       # Remove the borders of the image..
    flags[12]="-rotate '-90>'"         # Rotate the image if Height > Weight.
    flags[14]="-resize $resolution"    # Resize the image to our resoulion keeping ratio.
    flags[16]="-gravity center"        # Put it in the middle of the canvas.
    flags[18]="-extent $resolution"    # Then extend the rest, we'll always have full size images.
    flags[22]="-map /tmp/ct16gray.gif" # Use our custom color table.
    flags[20]="+dither"                # Reduce color without dithering.
    flags[24]="-compress zip"          # zip compression on the PDF.
    flags[26]="$escaped_outfile"       # Escaped output file, so it won't mess our eval.
    # Evaluate and create the pdf IF it does'nt exist.
    [ -f "$outfile" ] || eval "time convert -verbose $list ${flags[@]}"
    shift
done

# Remove our gif pallete.
[ -f /tmp/ct16gray.gif ] && rm /tmp/ct16gray.gif
