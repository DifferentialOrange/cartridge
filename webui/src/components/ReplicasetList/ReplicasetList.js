import React from 'react';
import { withRouter } from 'react-router-dom';
import { css, cx } from '@emotion/css';
import PropTypes from 'prop-types';
import { defaultMemoize } from 'reselect';
import { Button, HealthStatus, IconEdit, Text, TiledList, TiledListItem, Tooltip } from '@tarantool.io/ui-kit';

import { ClusterIssuesModal } from 'src/components/ClusterIssuesModal';
import ReplicasetRoles from 'src/components/ReplicasetRoles';
import ReplicasetServerList from 'src/components/ReplicasetServerList';
import { addSearchParams } from 'src/misc/url';

const styles = {
  header: css`
    position: relative;
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    padding-right: 103px;
  `,
  alias: css`
    flex-basis: 458px;
    flex-grow: 1;
    flex-shrink: 0;
    margin-right: 16px;
    margin-bottom: 8px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  `,
  statusGroup: css`
    display: flex;
    flex-basis: 592px;
    flex-shrink: 0;
    margin-right: -55px;
    margin-bottom: 12px;
  `,
  statusWrap: css`
    flex-shrink: 0;
    flex-basis: 193px;
  `,
  status: css`
    display: flex;
    align-items: center;
    height: 22px;
    margin-left: -8px;
    margin-right: 12px;
  `,
  statusWarning: css`
    color: rgba(245, 34, 45, 0.65);
  `,
  statusButton: css`
    display: block;
    padding-left: 8px;
    padding-right: 8px;
    margin-left: -8px;
    margin-top: -1px;
    margin-bottom: -1px;
  `,
  vshardTooltip: css`
    display: inline;
    font-weight: bold;
  `,
  vshard: css`
    position: absolute;
    right: 76px;
    width: 343px;
    margin-left: 12px;
    margin-right: 12px;
    color: rgba(0, 0, 0, 0.65);

    & > * {
      position: relative;
      margin-right: 17px;

      &::before {
        content: '';
        position: absolute;
        top: 0px;
        right: -8px;
        width: 1px;
        height: 18px;
        background-color: #e8e8e8;
      }
    }

    & > *:last-child {
      margin-right: 0;

      &::before {
        content: none;
      }
    }
  `,
  editBtn: css`
    position: absolute;
    top: 1px;
    right: 0;
    flex-shrink: 0;
  `,
  roles: css`
    margin-top: 0;
    margin-bottom: 12px;
  `,
  divider: css`
    height: 1px;
    margin-top: 16px;
    margin-bottom: 12px;
    background-color: #e8e8e8;
  `,
};

const prepareReplicasetList = (dataSource) =>
  [...dataSource].sort((a, b) => {
    let aValue = a.alias || '';
    let bValue = b.alias || '';

    if (aValue === bValue) {
      aValue = a.servers[0].alias || '';
      bValue = b.servers[0].alias || '';
    }

    if (aValue === bValue) {
      aValue = a.uuid;
      bValue = b.uuid;
    }

    return aValue < bValue ? -1 : 1;
  });

class ReplicasetList extends React.PureComponent {
  state = {
    showReplicasetIssues: null,
  };

  hideIssuesModal = () => this.setState({ showReplicasetIssues: null });

  showIssuesModal = (replicasetUUID) => this.setState({ showReplicasetIssues: replicasetUUID });

  prepareReplicasetList = defaultMemoize(prepareReplicasetList);

  render() {
    const { className, clusterSelf, editReplicaset, issues, joinServer, createReplicaset, onServerLabelClick } =
      this.props;

    const { showReplicasetIssues } = this.state;

    const replicasetList = this.getReplicasetList();

    const replicasetsWithIssues = issues
      .filter(({ replicaset_uuid }) => !!replicaset_uuid)
      .map(({ replicaset_uuid }) => replicaset_uuid);

    return (
      <>
        <TiledList className={className} outer={false}>
          {replicasetList.map((replicaset) => (
            <TiledListItem key={replicaset.uuid} corners="soft">
              <div className={styles.header} data-cy="meta-test__replicaSetSection">
                <Text className={styles.alias} variant="h3">
                  {replicaset.alias}
                </Text>
                <div className={styles.statusGroup}>
                  <div className={styles.statusWrap}>
                    {replicasetsWithIssues.includes(replicaset.uuid) ? (
                      <Button
                        className={cx(styles.statusButton, 'meta-test__haveIssues')}
                        intent="plain"
                        size="s"
                        onClick={() => this.showIssuesModal(replicaset.uuid)}
                      >
                        <HealthStatus
                          className={cx(styles.status, styles.statusWarning)}
                          message="have issues"
                          status="bad"
                        />
                      </Button>
                    ) : (
                      <HealthStatus className={styles.status} message={replicaset.message} status={replicaset.status} />
                    )}
                  </div>
                  <Text className={styles.vshard} variant="p" tag="div" upperCase>
                    {(replicaset.vshard_group || replicaset.weight) && (
                      <>
                        <Tooltip className={styles.vshardTooltip} content="Storage group">
                          {replicaset.vshard_group}
                        </Tooltip>
                        <Tooltip className={styles.vshardTooltip} content="Replica set weight">
                          {replicaset.weight}
                        </Tooltip>
                      </>
                    )}
                    {replicaset.all_rw && (
                      <Tooltip
                        className={cx(styles.vshardTooltip, 'meta-test__ReplicasetList_allRw_enabled')}
                        content="All instances in the replicaset writeable"
                      >
                        all rw
                      </Tooltip>
                    )}
                  </Text>
                </div>
                <Button
                  className={styles.editBtn}
                  icon={IconEdit}
                  intent="secondary"
                  onClick={() => this.handleEditReplicasetRequest(replicaset)}
                  text="Edit"
                  data-cy="meta-test__editBtn"
                />
              </div>
              <ReplicasetRoles className={styles.roles} roles={replicaset.roles} />
              <div className={styles.divider} />
              <ReplicasetServerList
                clusterSelf={clusterSelf}
                replicaset={replicaset}
                editReplicaset={editReplicaset}
                joinServer={joinServer}
                createReplicaset={createReplicaset}
                onServerLabelClick={onServerLabelClick}
              />
            </TiledListItem>
          ))}
        </TiledList>
        <ClusterIssuesModal
          visible={showReplicasetIssues || false}
          issues={issues.filter(({ replicaset_uuid }) => replicaset_uuid === showReplicasetIssues)}
          onClose={this.hideIssuesModal}
        />
      </>
    );
  }

  getReplicasetList = () => {
    const { dataSource } = this.props;
    return this.prepareReplicasetList(dataSource);
  };

  handleEditReplicasetRequest = (replicaset) => {
    const { history, location } = this.props;
    history.push({
      search: addSearchParams(location.search, { r: replicaset.uuid }),
    });
  };
}

ReplicasetList.propTypes = {
  clusterSelf: PropTypes.any,
  dataSource: PropTypes.arrayOf(
    PropTypes.shape({
      uuid: PropTypes.string,
    })
  ).isRequired,
  editReplicaset: PropTypes.func.isRequired,
  joinServer: PropTypes.func.isRequired,
  createReplicaset: PropTypes.func.isRequired,
  onServerLabelClick: PropTypes.func,
};

export default withRouter(ReplicasetList);
