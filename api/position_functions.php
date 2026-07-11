<?php
declare(strict_types=1);

function positionDatabase(): PDO
{
    $dsn = getenv('SUPABASE_DB_DSN') ?: '';
    $user = getenv('SUPABASE_DB_USER') ?: '';
    $password = getenv('SUPABASE_DB_PASSWORD') ?: '';

    if ($dsn === '' || $user === '' || $password === '') {
        throw new RuntimeException('Supabase database environment variables are not configured.');
    }

    return new PDO($dsn, $user, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

function validatePositionScope(array $scope): array
{
    $required = ['school_id', 'academic_year', 'term', 'programme_id', 'class_id'];
    foreach ($required as $field) {
        if (!isset($scope[$field]) || trim((string) $scope[$field]) === '') {
            throw new InvalidArgumentException("Missing required field: {$field}");
        }
    }

    foreach (['school_id', 'programme_id', 'class_id'] as $field) {
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', (string) $scope[$field])) {
            throw new InvalidArgumentException("Invalid UUID for {$field}");
        }
    }
    if (!preg_match('/^\d{4}\/\d{4}$/', (string) $scope['academic_year'])) {
        throw new InvalidArgumentException('Academic year must use YYYY/YYYY format.');
    }

    return array_map(static fn($value) => trim((string) $value), $scope);
}

/**
 * Return the best-three Core total, best-three Elective total, and overall total.
 * Subject classification always comes from subjects.subject_type.
 */
function calculateStudentBestScores(PDO $pdo, array $scope, string $studentId): array
{
    $sql = <<<'SQL'
        select
            sub.id as subject_id,
            sub.subject_type,
            round(sum(
                case
                    when score.score is null then 0
                    when assessment.overall_score is not null and assessment.overall_score > 0
                        then least((score.score / assessment.overall_score) * mode.weight_percent, mode.weight_percent)
                    else (score.score * mode.weight_percent / 100.0)
                end
            ), 2) as subject_total
        from public.assessment_scores score
        join public.assessments assessment on assessment.id = score.assessment_id
        join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
        join public.subjects sub on sub.id = assessment.subject_id
        where score.student_id = :student_id
          and assessment.school_id = :school_id
          and assessment.class_id = :class_id
          and assessment.academic_year = :academic_year
          and assessment.semester = :term
        group by sub.id, sub.subject_type
        SQL;

    $statement = $pdo->prepare($sql);
    $statement->execute([
        'student_id' => $studentId,
        'school_id' => $scope['school_id'],
        'class_id' => $scope['class_id'],
        'academic_year' => $scope['academic_year'],
        'term' => $scope['term'],
    ]);

    $core = [];
    $elective = [];
    foreach ($statement->fetchAll() as $subject) {
        $score = round((float) $subject['subject_total'], 2);
        if (strtolower((string) $subject['subject_type']) === 'core') {
            $core[] = $score;
        } else {
            $elective[] = $score;
        }
    }

    rsort($core, SORT_NUMERIC);
    rsort($elective, SORT_NUMERIC);
    $coreTotal = round(array_sum(array_slice($core, 0, 3)), 2);
    $electiveTotal = round(array_sum(array_slice($elective, 0, 3)), 2);

    return [
        'student_id' => $studentId,
        'best_three_core_total' => $coreTotal,
        'best_three_elective_total' => $electiveTotal,
        'overall_total' => round($coreTotal + $electiveTotal, 2),
    ];
}

/** Upsert one result summary without creating duplicates. */
function updateStudentPosition(PDO $pdo, array $scope, array $result): void
{
    $sql = <<<'SQL'
        insert into public.result_summaries (
            school_id, academic_year, term, programme_id, class_id, student_id,
            best_three_core_total, best_three_elective_total, overall_total,
            class_position, class_size, calculated_at
        ) values (
            :school_id, :academic_year, :term, :programme_id, :class_id, :student_id,
            :core_total, :elective_total, :overall_total,
            :class_position, :class_size, now()
        )
        on conflict (school_id, academic_year, term, programme_id, class_id, student_id)
        do update set
            best_three_core_total = excluded.best_three_core_total,
            best_three_elective_total = excluded.best_three_elective_total,
            overall_total = excluded.overall_total,
            class_position = excluded.class_position,
            class_size = excluded.class_size,
            calculated_at = excluded.calculated_at
        SQL;

    $statement = $pdo->prepare($sql);
    $statement->execute([
        'school_id' => $scope['school_id'],
        'academic_year' => $scope['academic_year'],
        'term' => $scope['term'],
        'programme_id' => $scope['programme_id'],
        'class_id' => $scope['class_id'],
        'student_id' => $result['student_id'],
        'core_total' => $result['best_three_core_total'],
        'elective_total' => $result['best_three_elective_total'],
        'overall_total' => $result['overall_total'],
        'class_position' => $result['class_position'],
        'class_size' => $result['class_size'],
    ]);
}

/** Calculate and persist standard-competition class positions for one exact scope. */
function calculateClassPositions(PDO $pdo, array $scope): array
{
    $scope = validatePositionScope($scope);
    $pdo->beginTransaction();

    try {
        $studentQuery = $pdo->prepare(<<<'SQL'
            select student.id
            from public.students student
            join public.classes class on class.id = student.class_id
            where student.school_id = :school_id
              and student.class_id = :class_id
              and class.programme_id = :programme_id
              and coalesce(student.status, 'Active') not in ('Transferred', 'Dropped', 'Completed')
            order by student.id
            SQL);
        $studentQuery->execute([
            'school_id' => $scope['school_id'],
            'class_id' => $scope['class_id'],
            'programme_id' => $scope['programme_id'],
        ]);
        $studentIds = array_column($studentQuery->fetchAll(), 'id');

        $results = [];
        foreach ($studentIds as $studentId) {
            $results[] = calculateStudentBestScores($pdo, $scope, (string) $studentId);
        }

        usort($results, static function (array $left, array $right): int {
            $scoreCompare = $right['overall_total'] <=> $left['overall_total'];
            return $scoreCompare !== 0 ? $scoreCompare : strcmp($left['student_id'], $right['student_id']);
        });

        $classSize = count($results);
        $previousTotal = null;
        $previousPosition = 0;
        foreach ($results as $index => &$result) {
            $sameTotal = $previousTotal !== null && abs($result['overall_total'] - $previousTotal) < 0.005;
            $result['class_position'] = $sameTotal ? $previousPosition : $index + 1;
            $result['class_size'] = $classSize;
            $previousTotal = $result['overall_total'];
            $previousPosition = $result['class_position'];
            updateStudentPosition($pdo, $scope, $result);
        }
        unset($result);

        $cleanup = $pdo->prepare(<<<'SQL'
            delete from public.result_summaries summary
            where summary.school_id = :school_id
              and summary.academic_year = :academic_year
              and summary.term = :term
              and summary.programme_id = :programme_id
              and summary.class_id = :class_id
              and not exists (
                  select 1 from public.students student
                  where student.id = summary.student_id
                    and student.school_id = :school_id
                    and student.class_id = :class_id
                    and coalesce(student.status, 'Active') not in ('Transferred', 'Dropped', 'Completed')
              )
            SQL);
        $cleanup->execute($scope);

        $pdo->commit();
        return $results;
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $error;
    }
}

