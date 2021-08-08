    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Process variables
        id: variables
        run: |
          if [ -n "${{ matrix.shield }}" -a "${{ matrix.shield }}" != "default" ]

          then
            SHIELD_ARG="-DSHIELD=${{ matrix.shield }}"
            keyboard=${{ matrix.shield }}
            shield=${{ matrix.shield }}
          else
            keyboard=${{ matrix.board }}
            shield=""
          fi
          echo "::set-output name=shield-arg::${SHIELD_ARG}"
          keyboard=`echo "$keyboard" | sed 's/_\(left\|right\)//'`

          configfile="${GITHUB_WORKSPACE}/miryoku/config.h"
          echo '// https://github.com/manna-harbour/miryoku-zmk/' > "$configfile"
          echo "::set-output name=configfile::$configfile"

          artifact_build_name="miryoku_zmk $shield ${{ matrix.board }}"
          for option in "alphas_${{ matrix.alphas }}" "nav_${{ matrix.nav }}" "clipboard_${{ matrix.clipboard }}" "layers_${{ matrix.layers }}" "mapping_${{ matrix.mapping }}"
          do
            case "$option" in
              *_ ) ;;
              *_default ) ;;
              * )
                artifact_build_name="$artifact_build_name $option"
                echo "#define MIRYOKU_"`echo "$option" | tr 'a-z' 'A-Z'` >> "$configfile"
                ;;
            esac
          done
          artifact_build_name=`echo $artifact_build_name | tr ' ' '-'`
          echo "::set-output name=artifact-build-name::$artifact_build_name"
          echo "::set-output name=artifact-generic-name::"`echo "$artifact_build_name" | sed 's/_\(left\|right\)//'`
          echo "::set-output name=artifact-dir::artifacts"

          outboard_file=".github/workflows/outboards/$keyboard"
          if [ -f "$outboard_file" ]
          then
            cat "$outboard_file" >> $GITHUB_ENV
          fi
          echo "::set-output name=outboard_dir::outboard"
      - name: Checkout outboard
        if: ${{ env.outboard_repository != '' && env.outboard_ref != '' }}
        uses: actions/checkout@v2
        with:
          repository: ${{ env.outboard_repository }}
          ref: ${{ env.outboard_ref }}
          path: ${{ steps.variables.outputs.outboard_dir }}
      - name: Link outboard
        if: ${{ env.outboard_from != '' && env.outboard_to != '' }}
        run: |
          mkdir -p `dirname "config/${{ env.outboard_to }}"`
          ln -sr ${{ steps.variables.outputs.outboard_dir }}/${{ env.outboard_from }} config/${{ env.outboard_to }}
      - name: Generate outboard manifest
        if: ${{ env.outboard_url_base != '' && env.outboard_revision != '' }}
        run: |
          echo "manifest:\n  remotes:\n    - name: outboard\n      url-base: ${{ env.outboard_url_base }}\n  projects:\n    - name: zmk\n      remote: outboard\n      revision: ${{ env.outboard_revision }}\n      import: app/west.yml\n  self:\n    path: config" > config/west.yml
          cat config/west.yml
      - name: Copy outboard manifest
        if: ${{ env.outboard_manifest != '' }}
        run: |
          cp ${{ steps.variables.outputs.outboard_dir }}/${{ env.outboard_manifest }} config/west.yml
          cat config/west.yml
      - name: Cache west modules
        uses: actions/cache@v2
        env:
          cache-name: zephyr
        with:
          path: |
            bootloader/
            modules/
            tools/
            zephyr/
            zmk/
          key: ${{ runner.os }}-${{ env.cache-name }}-${{ hashFiles('config/west.yml') }}
          restore-keys: ${{ runner.os }}-${{ env.cache-name }}
        timeout-minutes: 2
        continue-on-error: true
      - name: Initialize workspace (west init)
        run: west init -l config
      - name: Update modules (west update)
        run: west update
      - name: Export Zephyr CMake package (west zephyr-export)
        run: west zephyr-export
      - name: Build (west build)
        run: west build -s zmk/app -b ${{ matrix.board }} -- ${{ steps.variables.outputs.shield-arg }} -DZMK_CONFIG="${GITHUB_WORKSPACE}/config"
      - name: Prepare artifacts
        run: |
          mkdir ${{ steps.variables.outputs.artifact-dir }}
          cp "${{ steps.variables.outputs.configfile }}" "${{ steps.variables.outputs.artifact-dir }}"
          for extension in "hex" "uf2"
          do
            file="build/zephyr/zmk.$extension"
            if [ -f "$file" ]
            then
              cp "$file" "${{ steps.variables.outputs.artifact-dir }}/${{ steps.variables.outputs.artifact-build-name }}.$extension"
            fi
          done
      - name: Archive artifacts
        uses: actions/upload-artifact@v2
        with:
          name: ${{ steps.variables.outputs.artifact-generic-name }}
          path: ${{ steps.variables.outputs.artifact-dir }}
        continue-on-error: true